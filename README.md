# Kinda

Kinda is a Zig-first binding framework for Elixir.

It is designed for projects that need to bind a large C API to BEAM without
hand-writing every NIF, resource wrapper, and dispatch stub.

The shortest useful description is:

- `kinda` treats a wrapper header as the binding surface
- extracts functions into a framework-owned manifest
- preserves Clang-extracted function docs when comments are available
- generates generic Zig/Elixir wrapper outputs
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

Generated `use Kinda.CodeGen` modules now also expose their declaration
manifest via `__kinda_nif_decls__/0`.

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
  functions: [
    %Kinda.Wrapper.Function{
      name: "mlirContextCreate",
      params: [],
      arity: 0,
      doc: "Creates a new MLIR context."
    }
  ]
}
```

### 2. Apply consumer policy

```elixir
defmodule MyLib.WrapperPolicy do
  @behaviour Kinda.Wrapper.Policy

  def unsupported_entries, do: %{}
  def unsupported?(_name), do: false
  def unsupported_reason(_name), do: nil

  def callback_bridge_entries, do: %{}
  def callback_bridge?(_name), do: false
  def callback_bridge(_name), do: nil

  def variants(name), do: [{:normal, name, name}]
  def public_name({_kind, public, _base}), do: public
  def elixir_params({_kind, _public, _base}, params), do: params
  def dirty({_kind, _public, _base}), do: false
  def zig_entry({_kind, _public, base}), do: ~s{nif("#{base}"),}
end
```

### 3. Generate outputs

```elixir
Kinda.Wrapper.Generate.render_elixir_manifest(manifest, MyLib.WrapperPolicy)
Kinda.Wrapper.Generate.render_zig_nif_entries(manifest, MyLib.WrapperPolicy)
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

## Reporting Surface

Kinda now exposes two reporting modes for that backlog:

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
