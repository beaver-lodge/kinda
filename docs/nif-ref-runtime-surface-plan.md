# Kinda NIF Ref Runtime-Surface Plan

## Summary

`kinda` currently mixes several different responsibilities into one practical
runtime path:

- generated NIF entrypoints
- public wrapper functions that unwrap inputs and normalize outputs
- `Kinda.Forwarder` as a consumer-owned runtime adapter
- `%Kind{ref: ref}` wrapper structs generated via `Kinda.ResourceKind`

The question is whether `kinda` should remove:

- `forward`
- generated NIF wrappers
- NIF ref wrapper structs

The answer from the `beaver` probe is:

- do not remove all three wholesale
- do split their responsibilities much more explicitly
- do narrow where wrapper structs are required and where plain terms should
  remain plain terms

The real problem is not "too many layers" in the abstract.
The real problem is that raw NIF calls, runtime normalization, and typed
Elixir-facing wrappers are still partially conflated.

## Current Status

The first explicit raw-vs-public runtime seam slice has now landed.

What is already true:

- `Kinda.Forwarder` now exposes:
  - `raw_call/3`
  - `call/3`
  - `forward/3`
  - `check!/1`
  - `to_term/1`
- `Kinda.ResourceKind.make/1` now routes through
  [Kinda.Forwarder.call_kind/4](/Users/tsai/oss/kinda/lib/forwarder.ex:99)
  instead of hard-coding `forward_module.forward(...)`
- generated public wrappers in
  [Kinda.CodeGen](/Users/tsai/oss/kinda/lib/kinda_codegen.ex:69)
  now route through
  [Kinda.Forwarder.invoke_public_nif/4](/Users/tsai/oss/kinda/lib/forwarder.ex:131)
  instead of each wrapper hand-rolling:
  - input unwrap
  - raw invoke
  - `check!/1`
- `beaver` now exposes a compatibility
  [Beaver.Native.call/3](/Users/tsai/oss/beaver/lib/beaver/native.ex:91)
  entry and probes it in
  [Beaver.Printer.create/0](/Users/tsai/oss/beaver/lib/beaver/printer.ex:10)

What is not yet true:

- raw/internal generated NIF surfaces are still not split into distinct
  modules or namespaces
- `forward/3` still exists as a compatibility shim
- the framework still does not classify native-facing shapes as:
  - `:resource`
  - `:transport`
  - `:plain`

## Why Beaver Is The Right Probe

`beaver` is the best stress test for this question because it uses `kinda`
across all the hard cases at once:

- many opaque MLIR handle kinds via
  [lib/beaver/mlir/capi_codegen.ex](/Users/tsai/oss/beaver/lib/beaver/mlir/capi_codegen.ex:1)
- many `use Kinda.ResourceKind` modules such as
  [context.ex](/Users/tsai/oss/beaver/lib/beaver/mlir/context.ex:1) and
  [operation.ex](/Users/tsai/oss/beaver/lib/beaver/mlir/operation.ex:1)
- a richer runtime adapter in
  [Beaver.Native](/Users/tsai/oss/beaver/lib/beaver/native.ex:1)
- extra wrapper structs for arrays, pointers, and opaque pointers in:
  - [array.ex](/Users/tsai/oss/beaver/lib/beaver/native/array.ex:1)
  - [ptr.ex](/Users/tsai/oss/beaver/lib/beaver/native/ptr.ex:1)
  - [opaque_ptr.ex](/Users/tsai/oss/beaver/lib/beaver/native/opaque_ptr.ex:1)

If a simplification breaks `beaver`, it is probably not a real framework
improvement.

## Current Kinda Runtime Path

Today the core path in `kinda` looks like this:

### 1. Input unwrapping

[Kinda.unwrap_ref/1](/Users/tsai/oss/kinda/lib/kinda.ex:6)
turns `%{ref: ref}` back into `ref`, recursively for lists.

This is consumed directly by generated wrappers in
[Kinda.CodeGen](/Users/tsai/oss/kinda/lib/kinda_codegen.ex:76).

### 2. Generated wrapper dispatch

Generated public wrappers currently:

- unwrap arguments with `Kinda.unwrap_ref/1`
- call a raw NIF function
- pass the result through `forward_module.check!/1`

That logic lives in
[Kinda.CodeGen](/Users/tsai/oss/kinda/lib/kinda_codegen.ex:69).

### 3. Runtime normalization

[Kinda.Forwarder](/Users/tsai/oss/kinda/lib/forwarder.ex:1)
now formalizes the first public runtime slice:

- `check!/1`
- `forward/3`
- `to_term/1`

This is enough for `kinda_example`, but it is still only the minimal path.

### 4. Typed wrapper structs

[Kinda.ResourceKind](/Users/tsai/oss/kinda/lib/resource_kind.ex:1)
generates `%Kind{ref: ref}` wrappers and a `make/1` constructor that delegates
through `forward_module.forward(__MODULE__, "make", [value])`.

That gives the Elixir side a typed identity for values that are represented by
native references.

## What Beaver Shows

`beaver` shows three important facts.

### 1. Typed wrappers are not accidental sugar

`beaver` relies heavily on module-typed wrappers such as:

- `%Beaver.MLIR.Context{}`
- `%Beaver.MLIR.Operation{}`
- `%Beaver.MLIR.Type{}`

These wrappers are not cosmetic.
They provide:

- type identity at the Elixir layer
- dispatch identity for kind-scoped operations
- a place for consumer APIs, protocols, and docs to hang
- a stable bridge from Elixir values back to native refs

Removing wrapper structs entirely would collapse too much semantic structure
into raw references or plain tuples.

### 2. One generic `check!/1` is not enough for every consumer

`beaver` extends the normalization path with richer semantics in
[Beaver.Native](/Users/tsai/oss/beaver/lib/beaver/native.ex:70):

- diagnostics-aware return decoding
- pointer and opaque pointer construction
- array helpers
- richer `to_term/1` behavior

So the lesson is not "runtime adapters are unnecessary".
The lesson is "there must be a framework-level runtime seam, but consumers need
room to specialize it".

### 3. Ref wrappers are not all the same kind of thing

`beaver` uses at least three distinct categories of wrappers:

1. resource/handle wrappers
   - MLIR contexts, operations, regions, attributes
2. pointer/array transport wrappers
   - `%Beaver.Native.Ptr{}`
   - `%Beaver.Native.Array{}`
   - `%Beaver.Native.OpaquePtr{}`
3. plain decoded BEAM terms
   - binaries
   - numbers
   - diagnostics lists

This means `kinda` should not force one universal `%Kind{ref: ref}` mental
model onto every native-facing shape.

## What Should Not Be Removed Wholesale

### 1. Do not remove wrapper structs wholesale

For resource-backed and identity-bearing native values, wrapper structs are the
right abstraction.

They should stay for:

- opaque handles
- stateful resources
- values that need type-specific operations or protocols

### 2. Do not remove the runtime adapter seam wholesale

`forward` in its current shape may be too implicit, but the framework still
needs a stable indirection layer between:

- raw NIF calls
- consumer-specific normalization policy

Without that seam, every downstream project would have to rebuild its own
runtime contract from scratch.

### 3. Do not remove generated public wrappers wholesale

The public wrappers currently own two useful jobs:

- input unwrapping
- output normalization

Exposing only raw NIF stubs would leak ref-handling conventions into every call
site and make the Elixir API more fragile and repetitive.

## What Should Change

The current issue is not the existence of these layers.
The issue is that they are not explicit enough.

The framework should split the runtime surface into three named layers.

### Layer 1. Raw NIF surface

This layer should:

- call directly into the loaded NIF
- do no Elixir-side unwrap or wrap logic
- be treated as internal or explicitly low-level

Examples:

- `Raw.make/1`
- `Raw.primitive/1`
- `Raw.ptr/1`

### Layer 2. Runtime normalization surface

This layer should own:

- argument unwrapping
- result normalization
- standardized error decoding
- consumer-overridable runtime policy

This is where the current `Kinda.Forwarder` responsibility belongs, but with a
clearer contract than the current single `forward/3` entrypoint.

### Layer 3. Typed public Elixir surface

This layer should own:

- resource wrapper structs
- typed constructors/accessors
- public docs/specs
- consumer-facing ergonomic functions

This is where `%Kind{ref: ref}` belongs when the value really is a typed native
entity.

## Proposed Direction

### Decision 1. Keep wrapper structs, but narrow their scope

`Kinda.ResourceKind` should remain for resource/handle-like values.

Future evolution should add a more explicit distinction between:

- resource-backed kinds
- transport wrappers
- plain decoded values

That means the framework should stop implying that every native-facing type
must become a resource wrapper struct.

### Decision 2. Keep a runtime adapter seam, but demote bare `forward/3`

The framework should not center its long-term API on:

- `forward(module, function, args)`

That shape is too magical and too string/atomly typed as the main public story.

Instead, evolve toward a clearer runtime contract, for example:

- raw call surface
- argument normalization
- result normalization
- `to_term/1`

`forward/3` can remain as a compatibility shim while the clearer split lands.

### Decision 3. Keep generated public wrappers, but split them from raw stubs

Today `Kinda.CodeGen` effectively mixes:

- raw NIF entrypoint emission
- public normalized wrapper emission

Those should become explicitly separate.

The framework should generate:

1. a raw/internal call surface
2. a normalized/public wrapper surface

That makes the wrap/unwrap story easier to reason about and easier to evolve.

## Evolution Phases

### Phase 1. Document the runtime layers

Goal: make the current implicit model explicit.

- land this plan
- describe the distinction between:
  - raw NIF calls
  - runtime normalization
  - typed public wrappers
- stop describing wrapper structs and forwarders as one undifferentiated thing

Status:

- this phase has landed
- and the first code slice after the documentation pass has now landed too:
  - explicit `raw_call/3` and `call/3` runtime helpers
  - `ResourceKind.make/1` using `call_kind/4`
  - generated public wrappers using `invoke_public_nif/4`

### Phase 2. Split raw and public generated surfaces

Goal: stop conflating low-level NIF entrypoints with normalized public wrappers.

- teach `Kinda.CodeGen` to emit an explicit raw layer
- keep public wrappers as the normalization layer above it
- keep existing public APIs stable via compatibility shims where needed

Current status:

- the raw-vs-public seam is now explicit in helper form
- but it is not yet explicit in generated module layout or naming
- that means this phase is partially prepared, not completed

### Phase 3. Introduce kind-shape classification

Goal: stop forcing every native-facing type into the same wrapper model.

Add a framework-owned classification such as:

- `:resource`
- `:transport`
- `:plain`

And let generation/runtime policy differ accordingly.

Examples:

- MLIR handles stay `:resource`
- pointers/opaque pointers/arrays become `:transport`
- decoded numbers/binaries remain `:plain`

### Phase 4. Replace bare `forward/3` as the primary story

Goal: make runtime semantics explicit instead of magical.

- keep `forward/3` for compatibility first
- introduce a clearer runtime API centered on:
  - argument unwrap
  - raw invoke
  - result normalization
  - `to_term/1`
- migrate `kinda_example` first
- then probe the new shape with one bounded `beaver` slice

### Phase 5. Probe the split in Beaver

Goal: verify that the new model survives a real large consumer.

Use one bounded migration slice in `beaver`:

- one MLIR resource handle path
- one plain decoded value path
- one pointer/array transport path

If that split feels clearer and reduces downstream adapter code, continue.
If it increases boilerplate, adjust before larger migration.

## Immediate Recommendation

The next concrete runtime work in `kinda` should be:

1. keep `%Kind{ref: ref}` for true resource/handle wrappers
2. stop treating that wrapper model as universal
3. make raw-vs-public generated surfaces explicit
4. treat `forward/3` as a transitional API, not the final user-facing design
5. use `beaver` to validate each runtime-surface simplification before
   generalizing it

## Bottom Line

`beaver` does not support the conclusion that `kinda` should simply remove:

- `forward`
- generated NIF wrappers
- ref wrapper structs

It supports a narrower and more useful conclusion:

- keep typed wrappers where identity matters
- keep a runtime normalization seam
- keep generated public wrappers
- but split raw calls, runtime normalization, and typed public wrappers into a
  much more explicit framework design
