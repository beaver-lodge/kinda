# Kinda Direct NIF Runtime Surface

## Summary

Kinda separates native binding calls into three explicit layers:

1. a raw NIF surface
2. a boundary codec
3. typed public Elixir modules

There is no consumer-owned runtime dispatcher between these layers. Generated
code resolves the raw module and function at compile time. The consumer codec
only normalizes the value returned by that concrete call.

## Raw NIF Surface

`Kinda.CodeGen` emits a companion `RootModule.Raw` module. Its functions call
the concrete NIF stubs in the root module directly.

Raw functions:

- accept native BEAM representations
- do not unwrap resource structs
- do not normalize `{:kind, module, ref}` tuples
- remain available for low-level integrations

Generated public wrappers call the same raw functions with statically generated
remote-call AST. They do not route calls through a consumer module and do not
use runtime `apply/3` dispatch.

## Boundary Codec

`Kinda.Codec` owns returned-value representation only.

The default `normalize/1` implementation:

- turns `{:kind, module, ref}` into `%module{ref: ref}`
- preserves metadata paired with kind tuples
- raises structured native errors
- leaves plain values unchanged

Consumers can `use Kinda.Codec` and override `normalize/1` for product-specific
representations such as diagnostics, arrays, and opaque pointers.

A codec does not know the raw NIF module, native function name, or argument
list. This keeps dispatch separate from representation policy.

## Typed Public Surface

`Kinda.CodeGen` receives a `codec:` option:

```elixir
use Kinda.CodeGen,
  with: MyLibrary.Generated,
  root: MyLibrary.CAPI,
  codec: MyLibrary.Native
```

For public/raw name splits, the generated public function:

1. unwraps each argument with `Kinda.unwrap_ref/1`
2. calls the concrete function in `MyLibrary.CAPI.Raw`
3. passes the result to `MyLibrary.Native.normalize/1`

The generated root NIF stubs remain the functions replaced by
`:erlang.load_nif/2`.

## Resource Kinds

`Kinda.ResourceKind` binds explicitly to the raw module and codec:

```elixir
use Kinda.ResourceKind,
  raw_module: MyLibrary.CAPI.Raw,
  codec: MyLibrary.Native
```

Its generated `make/1` calls the concrete kind-scoped raw constructor and then
normalizes the result. It does not require a runtime module that owns function
selection.

Resource structs remain appropriate for:

- opaque handles
- stateful native resources
- values with type-specific operations or protocols

Plain native results do not need resource wrappers.

## Consumer Specialization

Beaver is the primary stress test for the split because it combines:

- many MLIR handle kinds
- diagnostics-aware results
- arrays and typed pointers
- opaque-pointer transport
- handwritten callback resources

Beaver keeps these representation policies in `Beaver.Native.normalize/1` while
calling `Beaver.MLIR.CAPI.Raw` explicitly for kind-scoped helpers.

## Non-goals

This surface does not:

- remove typed resource structs
- expose only raw references to public callers
- infer callback ownership or scheduler semantics
- implement the callback-bridge runtime

Those callback semantics remain a separate declaration and runtime concern.
