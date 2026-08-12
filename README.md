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
- the `kinda_sqlite` driver and multi-NIF coexistence suite

run:

```sh
mix kinda.verify
```

This is the command CI should prefer for repo-level verification.

If you only want the bundled application example from the repo root, run:

```sh
mix kinda.example.verify
```

The SQLite integration can be verified independently with:

```sh
mix kinda.sqlite.verify
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

## What Kinda Ships Today

Core runtime/building blocks:

- `Kinda.ResourceKind`
- `Kinda.CodeGen`
- `Kinda.Precompiler`
- `Kinda.Codec`
- `Kinda.CallbackRuntime` for the common BEAM callback/reply boundary
- `kinda.callback_runtime` for Zig-side native-thread callbacks into BEAM
- `beam.ResourceRef(T)` for retaining parent resources from child resources

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
3. callback-bridge backlog and runtime substrate

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

Define a boundary codec, generate the raw NIF surface, and bind a resource kind
directly to it:

```elixir
defmodule Foo.Native do
  use Kinda.Codec
end

defmodule Foo.CAPI.Raw do
  use Kinda.CodeGen,
    with: Foo.Generated,
    root: Foo.CAPI,
    codec: Foo.Native,
    surface: :raw

  @on_load :load_nif

  def load_nif do
    :erlang.load_nif(~c"path/to/foo_nif", 0)
  end
end

defmodule Foo.CAPI do
  use Kinda.CodeGen,
    with: Foo.Generated,
    root: __MODULE__,
    raw_module: __MODULE__.Raw,
    codec: Foo.Native,
    surface: :public
end

defmodule Foo.Handle do
  use Kinda.ResourceKind,
    raw_module: Foo.CAPI.Raw,
    codec: Foo.Native
end
```

Generated public wrappers call concrete functions in `Foo.CAPI.Raw`, unwrap
resource arguments, and pass only the returned value through `Foo.Native`.
The codec never selects a native function. Keeping `:public` wrappers and
`:raw` NIF stubs in separate modules lets large bindings compile both surfaces
independently and avoids a generated proxy layer. The raw module owns NIF
loading, so the native entry module must be `Elixir.Foo.CAPI.Raw`.

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

## Structured NIF Call Errors

Generated NIF failures raise `Kinda.CallError`. The legacy `:message` remains
available, while stable fields identify the failed function and boundary
phase. Argument decoding failures also include the one-based argument index,
manifest parameter name, expected C type and the category of the original
Elixir value when those facts are available.

```elixir
try do
  Foo.CAPI.add(1, "2")
rescue
  error in Kinda.CallError ->
    error.phase
    #=> :argument_decode

    Exception.message(error)
    #=> "add/2 rejected argument #2 (rhs): expected int, got binary"
end
```

Internal native failures retain the native Zig error name and suggest
`KINDA_DUMP_STACK_TRACE=1`. Caller-correctable argument errors omit that hint.

Other framework boundaries use the same structured-error approach:

- `Kinda.GenerationError` identifies declaration and code-generation failures
  with stable `:stage` and `:reason` fields plus the source, expected and actual
  values when relevant.
- `Kinda.CommandError` retains the command, arguments, working directory, exit
  status and captured output from failed `mix`, `zig` or other tool invocations.
- `Kinda.NIFLoadError` retains the attempted library path and the original
  `:erlang.load_nif/2` reason instead of printing the failure and continuing.

This keeps terminal messages useful while allowing Mix tasks and downstream
projects to handle failures without parsing those messages.

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

This metadata does not invent a consumer ABI automatically. It is the
framework-owned policy layer that lets a consumer say:

- this API is not “missing”
- this API belongs to the callback-bridge backlog, or is resolved by the
  dispatcher runtime

Pure kind-surface gaps belong to a different path. In a consumer such as
`beaver`, handle-like CAPIs are often unblocked by extending the Zig-side kind
surface and the matching Elixir `KindDecl` surface; callback-bridge metadata is
specifically for the remainder that kind-surface sync cannot solve.

## Callback Runtime

Consumers can implement those callback bridges with the generic Zig runtime:

```zig
const kinda = @import("kinda");
const Dispatcher = kinda.callback_runtime.Dispatcher(.{ "run", "destruct" });

const dispatcher = try Dispatcher.initWithOptions(handler_pid, .{
    .timeout_ms = 30_000,
});
dispatcher.setCallback("run", run_callback_term);
const response = try dispatcher.invoke("run", message_env, .{argument_term});
```

On the BEAM side, the consumer supplies its own reply NIF while Kinda
normalizes success, expected failure, and exceptions:

```elixir
Kinda.CallbackRuntime.invoke(
  reply_token,
  fn -> {:ok, run_callback.()} end,
  &MyNative.my_raw_callback_reply/2
)
```

Callbacks with scalar, enum, or projected handle results use
`invoke_reply/4`. The consumer validates its own resource before completing
the shared token:

```elixir
Kinda.CallbackRuntime.invoke_reply(reply_token, callback, fn token, outcome ->
  MyNative.reply_projected_result(token, outcome)
end)
```

The consuming NIF library exports and opens the shared reply resource:

```zig
const callback_nifs = .{
    kinda.callback_runtime.ReplyToken.nif("my_raw_callback_reply"),
    kinda.callback_runtime.ReplyToken.codeNif("my_raw_callback_reply_code"),
    kinda.callback_runtime.ReplyToken.cancelNif("my_raw_callback_cancel"),
};

export fn nif_load(env: kinda.beam.env, _: [*c]?*anyopaque, _: kinda.beam.term) c_int {
    kinda.callback_runtime.ReplyToken.open(env);
    return 0;
}
```

`Dispatcher` owns copied callback terms and its persistent environment. Each
invocation sends
`{callback_name, reply_token, callback_fun, dispatcher_id, ...args}`, then
waits on a non-scheduler native thread. The process replying through the
consumer-exported NIF becomes the next callback owner. Native callback
signatures, argument conversion, domain state, and diagnostics remain the
consumer's responsibility.

Waits are bounded to 30 seconds by default. A response reports whether it was
replied, canceled, dropped, or timed out; completion after any terminal state
returns `stale`. Dropping the reply resource or terminating its owner therefore
cannot leave a native worker waiting forever. `ReplyToken` and consumer-owned
registration resources use NIF resource-type takeover so live resources keep
the correct native library generation pinned across reload and unload.

`kinda.callback_adapter` provides the reusable projection shapes used by
consumer ABI trampolines: one handle, ranges of handles, scalar results, enum
results, and validated consumer projections. It never interprets an MLIR- or
library-specific handle.

Callback-bridge manifest version 2 records `runtime_backed`, `runtime`,
`owner`, `destructor`, `lifetime`, `scheduler`, and `timeout_ms`. Entries built
with `Kinda.Wrapper.CallbackBridge.runtime_backed/2` no longer carry a
`callback_bridge_required` blocker and their consumer-provided declaration
variant remains in the normal resolved declaration surface.

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

- policy-driven generation from callback metadata to runtime adapters
- richer scheduler-aware NIF declaration surface
- a complete prebuilt/download/checksum story
- a more polished one-command reporting UX

## Status

Kinda is already useful as a framework substrate.

It is now moving from:

- “resource kind + codegen helper”

toward:

- “wrapper-driven Zig/Elixir binding framework with explicit policy and backlog
  surfaces”

That is the right frame to evaluate future work.
