# Kinda

Kinda is a Zig-first binding framework for Elixir.

It is designed for projects that need to bind a large C API to BEAM without
hand-writing every NIF, resource wrapper, and dispatch stub.

The shortest useful description is:

- `kinda` treats a wrapper header as the binding surface
- extracts functions into a framework-owned manifest
- extracts named C records and field types into that same framework-owned manifest
- preserves Clang-extracted function docs when comments are available
- preserves raw C parameter/return type facts in that manifest
- generates generic Zig/Elixir wrapper outputs
- lets consumer policy project those raw C facts into public Elixir typespecs
- lets the same typed projection describe public record/field types in a
  machine-readable signature manifest
- lets the consumer keep product-specific policy outside the framework

This makes `kinda` a better fit for projects like `beaver`, where the problem
is not “write one ergonomic NIF”, but “keep a large drifting native API
coherent over time”.

## Run One Example

If you want the shortest stable repo-local proof of the wrapper/reporting
surface, run:

```sh
mix kinda.wrapper.example
```

Useful modes:

```sh
mix kinda.wrapper.example --json
mix kinda.wrapper.example --report-only
```

To verify the whole repo from the root, including:

- root tests
- wrapper-reporting JSON smoke
- bundled `kinda_example`

run:

```sh
mix kinda.verify
```

This is also the root verifier used by the checked-in `.restraint.exs`, and it
is the command CI should prefer for repo-level verification.

If you only want the bundled application example from the repo root, run:

```sh
mix kinda.example.verify
```

If you want the same thing without compiling the project first, run:

```sh
elixir examples/wrapper_reporting.exs
```

It prints:

- the generated Elixir wrapper manifest
- the machine-readable typed signature manifest
- the human-readable callback-bridge backlog report
- the machine-readable callback-bridge manifest
- including dirty scheduler metadata when the example policy emits it

The formal plan for how:

- `examples/`
- `kinda_example/`

fit together is:

- [docs/example-surface-unification-plan.md](/Users/tsai/oss/kinda/docs/example-surface-unification-plan.md:1)

## What Kinda Ships Today

Core runtime/building blocks:

- `Kinda.ResourceKind`
- `Kinda.CodeGen`
- `Kinda.Precompiler`
- `Kinda.Forwarder`

Wrapper extraction/generation blocks:

- `Kinda.Wrapper.Function`
- `Kinda.Wrapper.Manifest`
- `Kinda.Wrapper.Extract`
- `Kinda.Wrapper.Generate`
- `Kinda.Wrapper.Policy`
- `Kinda.Wrapper.CallbackBridge`

That means `kinda` now has an explicit split between:

1. generic wrapper extraction/generation
2. consumer-owned policy
3. future callback-bridge backlog

## Mental Model

Kinda is not primarily a “write NIFs directly in Zig” library.

It is a framework for binding a C library through three layers:

1. wrapper surface
   - a `.h` file says what native functions and types you want to expose
2. framework surface
   - `kinda` extracts that surface into a normalized manifest
   - `kinda` generates generic wrapper outputs from the manifest
3. consumer surface
   - your project decides naming, scheduler routing, diagnostics variants,
     unsupported APIs, and callback-heavy backlog

For a large binding, this is the important compression:

- `kinda` owns the generic mechanics
- your library owns the semantics

## Quick Example

Define a root runtime adapter and a resource kind:

```elixir
defmodule Foo.Native do
  use Kinda.Forwarder, nif_module: Foo.NIF
end

defmodule Foo.Handle do
  use Kinda.ResourceKind, forward_module: Foo.Native
end
```

Generate NIF-facing stubs from kinds and declarations:

```elixir
defmodule Foo.CAPI do
  use Kinda.CodeGen,
    with: Foo.Generated,
    root: __MODULE__,
    forward: Foo.Native
end
```

This is the older `ResourceKind + CodeGen` side of `kinda`.

Generated `use Kinda.CodeGen` modules now expose one formalized declaration
surface from the same typed source:

- the resolved declaration IR through `__kinda_declaration_surfaces__/0`

When a generator module implements `declaration_manifest/0`, `Kinda.CodeGen`
can now source generated function/type declarations directly from that unified
manifest instead of reconstructing them from parallel callbacks. That callback
is now the canonical declaration interface in `kinda`: it may return a loaded
manifest value or a checked-in `.ex` / `.json` sidecar path. Kind-derived
helper NIFs still come from `kinds()/0`.

`kinda` now also exposes a top-level downstream declaration facade through
`Kinda.Declaration`. That facade sits over the same underlying
`Kinda.CodeGen.DeclarationSurfaces` IR and formalizes the distinction between
the declaration source and the generated module surface:

- `Kinda.Declaration.load_source/1` reads the canonical source
  contract from a generator module
- `Kinda.Declaration.from_generator/2` resolves that source
  contract into the final generated surfaces for a specific root module,
  including normalized `nif_name`s, kind-derived helper entries,
  guaranteed/materialized generated `TypeDecl`s, and the derived signature
  view
- that resolved surface lands as the formal framework-owned IR:
  `Kinda.CodeGen.DeclarationSurfaces`

Downstreams should treat `Kinda.Declaration.from_generator/2` as the formalized
public resolution interface. Generated modules expose that same resolved IR
directly through `__kinda_declaration_surfaces__/0`.
Inside that IR, the canonical resolved payload is the declaration manifest
itself; `nif_decls`, `type_decls`, and `signature_manifest` are no longer
stored a second time on the resolved surface. That lets downstream repos such
as Beaver unify their own public rewrite/pass DSL names without re-owning the
declaration contract.

When that manifest includes projected records, `Kinda.CodeGen` also emits
deterministic public type aliases such as `foo_handle_record()/0` from the same
single source. These generated aliases use atom field keys derived from
extracted C field names, while the machine-readable manifest keeps the
original string names.

For larger generated bindings, the newer wrapper pipeline is usually more
important.

## Wrapper Pipeline

The wrapper pipeline is the part of `kinda` that scales to large native APIs.

### 1. Extract a manifest

```elixir
manifest = Kinda.Wrapper.Extract.from_clang_ast(ast_json)
```

The result is a framework-owned shape:

```elixir
%Kinda.Wrapper.Manifest{
  records: [
    %Kinda.Wrapper.CRecord{
      name: "MlirContext",
      kind: :struct,
      fields: [
        %Kinda.Wrapper.CField{
          name: "ptr",
          ctype: %Kinda.Wrapper.CType{spelling: "const void*", kind: :pointer}
        }
      ]
    }
  ],
  functions: [
    %Kinda.Wrapper.Function{
      name: "mlirContextCreate",
      params: [],
      arity: 0,
      doc: "Creates a new MLIR context.",
      param_ctypes: [],
      return_ctype: %Kinda.Wrapper.CType{
        spelling: "MlirContext",
        kind: :unknown
      }
    }
  ]
}
```

### 2. Apply consumer policy

```elixir
defmodule MyLib.WrapperPolicy do
  @behaviour Kinda.Wrapper.Policy

  def generation_blocker_entries, do: %{}
  def generation_blocked?(_name), do: false
  def generation_blocker_reason(_name), do: nil

  def callback_bridge_entries, do: %{}
  def callback_bridge?(_name), do: false
  def callback_bridge(_name), do: nil

  def variants(name), do: [{:normal, name, name}]
  def public_name({_kind, public, _base}), do: public
  def elixir_params({_kind, _public, _base}, params), do: params
  def dirty({_kind, _public, _base}), do: false
  def typespec_field(_record, field), do: ...
  def typespec_params(_variant, function), do: ...
  def typespec_return(_variant, function), do: ...
  def zig_entry({_kind, _public, base}), do: ~s{nif("#{base}"),}
end
```

### 3. Generate outputs

```elixir
Kinda.Wrapper.Generate.render_elixir_manifest(manifest, MyLib.WrapperPolicy)
Kinda.Wrapper.Generate.render_zig_nif_entries(manifest, MyLib.WrapperPolicy)
Kinda.Wrapper.Generate.declaration_surfaces_struct(manifest, MyLib.WrapperPolicy)
Kinda.Wrapper.Generate.declaration_manifest_struct(manifest, MyLib.WrapperPolicy)
Kinda.Wrapper.Generate.declaration_manifest(manifest, MyLib.WrapperPolicy)
```

## Callback-Bridge Backlog

Not every native function should be emitted as a plain generated wrapper.

Some functions need:

- callbacks back into BEAM
- richer decoder logic
- lifetime review
- scheduler review

Kinda now represents that explicitly with `Kinda.Wrapper.CallbackBridge`.

Example:

```elixir
Kinda.Wrapper.CallbackBridge.required(:some_function,
  scheduler: :dirty_cpu,
  facets: [:beam_callback, :scheduler_contract]
)
```

This is intentionally not the runtime bridge yet.
It is the framework-owned metadata layer that lets a consumer say:

- this API is not “missing”
- this API belongs to the callback-bridge backlog

Pure kind-surface gaps belong to a different path. In a consumer such as
`beaver`, handle-like CAPIs are often unblocked by extending the Zig-side kind
surface and the matching Elixir `KindDecl` surface; callback-bridge metadata is
specifically for the remainder that kind-surface sync cannot solve.

## Reporting Surface

Kinda now exposes one canonical declaration contract plus one derived signature
view around that wrapper surface:

1. resolved declaration surfaces
2. unified declaration manifest
3. callback-bridge manifest

Resolved declaration surfaces:

```elixir
Kinda.Wrapper.Generate.declaration_surfaces_struct(manifest, policy)
```

This is now the canonical wrapper-side in-memory declaration IR in `kinda`.
It carries:

- the source declaration-manifest slot, set to `nil` for wrapper-generated
  surfaces
- the canonical resolved declaration manifest

Unified declaration manifest:

```elixir
Kinda.Wrapper.Generate.declaration_manifest_struct(manifest, policy)
Kinda.Wrapper.Generate.declaration_manifest(manifest, policy)
```

The declaration-manifest struct is now the canonical resolved payload stored
inside `DeclarationSurfaces`, and the map form is the JSON-friendly
serialization. It keeps:

- named C records and fields from extraction
- raw C param/return type facts from extraction
- consumer-projected public params and return typespecs
- consumer-projected public record and field typespecs
- generated `NIFDecl` entries
- generated `TypeDecl` entries
- dirty scheduler metadata on emitted variants
- generation-blocker reasons when the function is not emitted as a plain
  generated wrapper

Internally, `Kinda.CodeGen.DeclarationManifest.build/2` is now the canonical
way to derive declaration metadata from typed wrapper facts, including the
generated `TypeDecl` layer. That keeps type declarations sourced from the same
declaration contract rather than from a parallel signature-only path.

When that declaration contract is consumed by `use Kinda.CodeGen`, the formal
resolution path now lives in `Kinda.CodeGen.DeclarationSurfaces.from_generator/2`,
so downstreams do not have to reimplement normalization or merge logic just to
observe the final generated declaration surface. That resolved surface is now
materialized as `Kinda.CodeGen.DeclarationSurfaces`, rather than an ad hoc map.

The typed signature manifest remains available as a derived compatibility view:

```elixir
Kinda.Wrapper.Generate.signature_manifest(manifest, policy)
```

The callback-bridge backlog remains a separate reporting mode:

1. human-readable report
2. machine-readable manifest

Human-readable:

```elixir
Kinda.Wrapper.Generate.render_callback_bridge_report(manifest, policy)
```

Machine-readable:

```elixir
Kinda.Wrapper.Generate.callback_bridge_manifest(manifest, policy)
```

The manifest is versioned and JSON-friendly:

```json
{
  "version": 1,
  "entries": [
    {
      "function": {
        "name": "mlirTypeConverterAddConversion",
        "arity": 1,
        "params": ["converter"]
      },
      "callback_bridge": {
        "function": "mlirTypeConverterAddConversion",
        "reason": "callback_bridge_required",
        "unblock_path": "callback_bridge_runtime",
        "scheduler": "unspecified",
        "facets": ["beam_callback", "rich_input_decoder"]
      }
    }
  ]
}
```

This is the main new “reporting surface” for consumers and CI.

The repo-local example above exercises this end to end.

## Build / Prebuilt Surface

Kinda ships `Kinda.Precompiler`, which consumers can use with `elixir_make`
precompiled builds.

Example:

```elixir
def project do
  [
    make_precompiler: {:nif, Kinda.Precompiler}
  ]
end
```

Today this is target-selection substrate, not a full RustlerPrecompiled-style
product story.

## What Kinda Is Good At

- binding large C APIs with repetitive structure
- generating resource-centric Elixir/Zig surfaces
- separating framework mechanics from consumer policy
- keeping callback-heavy APIs visible as backlog instead of hiding them in a
  flat blacklist
- acting as a binding substrate for projects that drift with upstream native
  APIs

## What Kinda Is Not Yet

Kinda is not yet a Rustler-complete framework.

What is still missing:

- a richer productized forwarder/runtime layer beyond the first
  `Kinda.Forwarder` slice
- callback bridge runtime implementation
- richer scheduler-aware NIF declaration surface
- a complete prebuilt/download/checksum story
- a more polished one-command reporting UX

## Where To Look Next

- wrapper split plan:
  - [docs/wrapper-extraction-split-plan.md](docs/wrapper-extraction-split-plan.md)
- real consumer analysis from `beaver`:
  - [../beaver/docs/kinda-integration-analysis.md](../beaver/docs/kinda-integration-analysis.md)

## Status

Kinda is already useful as a framework substrate.

It is now moving from:

- “resource kind + codegen helper”

toward:

- “wrapper-driven Zig/Elixir binding framework with explicit policy and backlog
  surfaces”

That is the right frame to evaluate future work.
