# Wrapper Extraction Split Plan

## Summary

The current `clang AST -> gen_stub.exs` pipeline in `beaver` should be
partially moved into `kinda`, but not copied wholesale.

The right move is:

- move the generic wrapper extraction and stub generation machinery into
  `kinda`
- keep MLIR-specific policy and wrapper composition in `beaver`

This preserves the framework boundary:

- `kinda` becomes a real binding-generation framework
- `beaver` remains an MLIR consumer with custom policy

## Current State

Today the pipeline is split across these `beaver` pieces:

- [build.zig](/Users/tsai/oss/beaver/build.zig:13)
- [native/tools/wrapper/gen_header.exs](/Users/tsai/oss/beaver/native/tools/wrapper/gen_header.exs:1)
- [native/tools/wrapper/gen_stub.exs](/Users/tsai/oss/beaver/native/tools/wrapper/gen_stub.exs:1)

The build currently does this:

1. generate `wrapper.h`
2. run `zig cc -E -Xclang -ast-dump=json`
3. pipe that JSON into `gen_stub.exs`
4. emit:
   - `generated/wrapper.zig`
   - `generated/capi_functions.ex`

This works, but it bundles together two different responsibilities:

1. generic extraction/generation
2. MLIR-specific policy

## Why This Should Be Split

`kinda` already claims a wrapper-driven model in its README:

- wrapper headers are the user-facing binding source
- kinds and NIF wrappers are generated from those wrapper files

But the current codebase does not yet ship a full wrapper extraction framework.
That leaves `beaver` carrying framework logic that belongs in `kinda`.

At the same time, `beaver`'s current generator contains clear MLIR-specific
policy:

- unsupported function blacklist
- diagnostics-aware dual NIF generation
- dirty CPU / dirty IO variants

That policy should not become `kinda` default behavior.

## Recommended Split

## Layer 1: Kinda Wrapper Extraction

Add a generic extraction layer in `kinda`, for example:

- `Kinda.Wrapper.Extract`

Responsibility:

- accept a wrapper header or AST input
- normalize discovered functions into a standard manifest
- expose:
  - function name
  - parameter names
  - arity
  - basic declaration metadata

Important:

- this layer may still use Clang AST internally
- there is no need to force a pure-Zig implementation first

Output shape should be stable and framework-owned, something like:

```elixir
%Kinda.Wrapper.Manifest{
  functions: [
    %Kinda.Wrapper.Function{
      name: :mlirFooBar,
      params: [:ctx, :value],
      arity: 2
    }
  ]
}
```

## Layer 2: Kinda Stub Generation

Add a generation layer in `kinda`, for example:

- `Kinda.Wrapper.Generate`

Responsibility:

- turn a manifest into:
  - Zig wrapper entries
  - Elixir NIF declaration manifests

This layer should be generic. It should not know about MLIR.

Its outputs should be equivalent in role to today's:

- `wrapper.zig`
- `capi_functions.ex`

but parameterized by generic framework inputs.

## Layer 3: Consumer Policy

Keep consumer-specific policy in the downstream project.

For `beaver`, that means preserving policy such as:

- unsupported NIFs
- diagnostics variants
- dirty CPU / dirty IO variants
- MLIR-specific naming and filtering

This can be expressed as a module or callback contract, for example:

```elixir
defmodule Beaver.MLIR.WrapperPolicy do
  @behaviour Kinda.Wrapper.Policy

  @impl true
  def classify(function) do
    ...
  end
end
```

Possible classifications:

- `:normal`
- `:with_diagnostics`
- `:dirty_cpu`
- `:dirty_io`
- `{:variants, [...]}`
- `:unsupported`

This keeps `kinda` generic while still letting `beaver` express MLIR-specific
dispatch policy.

## What Should Stay In Beaver

### 1. Wrapper composition

[native/tools/wrapper/gen_header.exs](/Users/tsai/oss/beaver/native/tools/wrapper/gen_header.exs:1)
should stay in `beaver`.

Why:

- it is composing an MLIR-specific wrapper surface
- it encodes what `beaver` wants to expose, not what `kinda` must expose

This is product policy, not framework substrate.

### 2. MLIR-specific function classification

The current rules in
[native/tools/wrapper/gen_stub.exs](/Users/tsai/oss/beaver/native/tools/wrapper/gen_stub.exs:1)
for diagnostics, dirty routing, and unsupported functions should move into a
`beaver` policy module, not into `kinda` defaults.

### 3. MLIR-specific handwritten NIF strategy

`beaver` has handwritten NIFs and runtime wiring beyond generic generated CAPI.
That remains `beaver`'s job.

## What Should Move Into Kinda

### 1. Clang AST ingestion

The mechanics of taking wrapper declarations and turning them into a normalized
manifest should live in `kinda`.

### 2. Manifest normalization

This should become a framework-owned schema, not an ad hoc shape embedded in
`gen_stub.exs`.

### 3. Generic Zig stub generation

The generic side of:

- `nif("foo")`
- arity-driven Elixir stub lists
- wrapper module declarations

belongs in `kinda`.

### 4. Generic Elixir manifest generation

The generation of `capi_functions.ex`-style metadata should be framework-owned,
with consumer hooks for classification and filtering.

## Migration Plan

### Phase 1: Introduce framework manifest in `kinda`

Add:

- `Kinda.Wrapper.Manifest`
- `Kinda.Wrapper.Function`
- `Kinda.Wrapper.Extract`

Goal:

- keep `beaver` output behavior unchanged
- just formalize the intermediate representation

### Phase 2: Extract generic generation from `gen_stub.exs`

Move the reusable parts of `gen_stub.exs` into:

- `Kinda.Wrapper.Generate`

Keep `beaver` invoking them from its build first, so the external behavior does
not change during the refactor.

### Phase 3: Add policy hook interface

Add:

- `Kinda.Wrapper.Policy`

Then move the current MLIR-specific classification rules from `beaver`'s
script into a policy module.

### Phase 4: Shrink `beaver` wrapper script

After phases 1-3, `beaver`'s wrapper generation should mostly reduce to:

1. compose `wrapper.h`
2. call `Kinda.Wrapper.Extract`
3. call `Kinda.Wrapper.Generate` with `Beaver` policy

At that point, the old `gen_stub.exs` can either disappear or become a very
thin project-local adapter.

### Phase 5: Reuse in another consumer

The split is only complete once a second consumer can use the same `kinda`
wrapper extraction/generation path without inheriting MLIR-specific policy.

Without that, the code is merely moved, not generalized.

## Non-Goals

### 1. Do not force a pure Zig-only pipeline

It is not necessary to remove Clang AST usage first.

The urgent problem is framework ownership and separation of concerns, not
implementation purity.

### 2. Do not move `wrapper.h` composition into `kinda`

That is consumer policy.

### 3. Do not bake MLIR policy into framework defaults

`kinda` should support policy hooks, not ship MLIR assumptions.

## Risks

### 1. Premature over-abstraction

If the manifest schema is too abstract too early, the split will become harder
to validate.

Recommendation:

- start with the smallest schema needed to represent today's `beaver` pipeline

### 2. Hidden dependence on Clang AST JSON shape

The current parser is coupled to the AST dump format.

Recommendation:

- isolate that coupling inside `Kinda.Wrapper.Extract`
- do not let it leak into generator APIs

### 3. Consumer policy creep

If `beaver` policy keeps leaking back into framework defaults, the split fails.

Recommendation:

- keep classification interfaces explicit
- test generic generation separately from `beaver`

## Success Criteria

This split is successful when:

1. `beaver` no longer owns generic wrapper extraction/generation logic
2. `kinda` exposes a stable wrapper manifest and generation API
3. `beaver` keeps only MLIR-specific wrapper composition and policy
4. a second consumer can reuse the framework without inheriting MLIR-specific
   behavior

## Bottom Line

Yes, this pipeline should move into `kinda`, but only after splitting it into:

- framework extraction
- framework generation
- consumer policy

That is the path that turns a useful `beaver`-local build trick into a genuine
`kinda` framework capability.
