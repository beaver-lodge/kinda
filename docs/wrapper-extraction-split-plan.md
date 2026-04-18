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

## Current Status

The first split slice has now landed.

What is already true:

- `kinda` now ships:
  - `Kinda.Wrapper.Function`
  - `Kinda.Wrapper.Manifest`
  - `Kinda.Wrapper.Extract`
  - `Kinda.Wrapper.Generate`
  - `Kinda.Wrapper.Policy`
  - `Kinda.Wrapper.CallbackBridge`
- `beaver` now ships:
  - `Beaver.MLIR.WrapperPolicy`
- `beaver`'s [gen_stub.exs](/Users/tsai/oss/beaver/native/tools/wrapper/gen_stub.exs:1)
  no longer walks Clang AST directly
- it now consumes:
  - `Kinda.Wrapper.Extract.from_clang_ast/1`
  - `Kinda.Wrapper.Generate.write_elixir_manifest/3`
  - `Kinda.Wrapper.Generate.write_zig_nif_entries/3`
- wrapper policy now also preserves dirty scheduler metadata through
  framework-owned `Kinda.CodeGen.NIFDecl` IR instead of only burying it inside
  Zig entry-string emission
- and classic `use Kinda.CodeGen` modules now expose those generated
  declarations through `__kinda_nif_decls__/0`, so the manifest is no longer
  only an intermediate file concern
- and the framework-owned wrapper manifest now preserves raw C parameter and
  return type facts via:
  - `Kinda.Wrapper.CType`
  - `Kinda.Wrapper.Function.param_ctypes`
  - `Kinda.Wrapper.Function.return_ctype`
- and `Kinda.Wrapper.Generate` / `Kinda.CodeGen` can now carry those typed
  facts forward into generated `NIFDecl` metadata and public `@spec`
  declarations
- and the policy surface now treats callback-heavy exclusions as
  generation-blockers first, with the older `unsupported_*` names retained only
  as compatibility aliases

What is not yet true:

- `beaver` still owns final emission policy
- callback-heavy MLIR APIs are still generation-blocked backlog, not yet
  bridged
- pure kind-surface gaps are now single-sourced in `beaver`, but the typed C
  signature projection contract is still consumer-specific rather than a full
  framework-level API
- scheduler metadata is now preserved in manifest IR, but `kinda` still does
  not expose a fully user-facing scheduler declaration/codegen contract
- but they are no longer only a flat reason atom
  - they now have a framework-owned callback-bridge metadata shape
  - and `Kinda.Wrapper.Generate` now exposes a callback-bridge backlog report
    surface
  - and a versioned machine-readable callback-bridge manifest contract

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
  - extracted docs when available
  - raw C parameter and return type facts

Important:

- this layer may still use Clang AST internally
- there is no need to force a pure-Zig implementation first

Output shape should be stable and framework-owned, something like:

```elixir
%Kinda.Wrapper.Manifest{
  functions: [
    %Kinda.Wrapper.Function{
      name: "mlirFooBar",
      params: ["ctx", "value"],
      arity: 2,
      param_ctypes: [
        %Kinda.Wrapper.CType{spelling: "MlirContext", kind: :unknown},
        %Kinda.Wrapper.CType{spelling: "intptr_t", kind: :integer}
      ],
      return_ctype: %Kinda.Wrapper.CType{spelling: "bool", kind: :bool}
    }
  ]
}
```

The current framework-owned IR keeps extracted names and params as strings.
Policy/generation layers convert to atoms at the consumer boundary when needed.

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

## Kind-Surface Auto-Unblock Path

There is an important middle case between:

- plain generated wrappers that already work
- callback-heavy APIs that need a future bridge layer

That middle case is "the function shape is ordinary, but the generated kind
surface is incomplete".

`beaver` currently expresses that surface in two places:

- Zig-side generated/resource kinds in
  [native/src/mlir_capi.zig](/Users/tsai/oss/beaver/native/src/mlir_capi.zig:1)
- Elixir-side `KindDecl` emission in
  [lib/beaver/mlir/capi_codegen.ex](/Users/tsai/oss/beaver/lib/beaver/mlir/capi_codegen.ex:1)

For handle-like or struct-like CAPIs, unblocking often means:

1. add the missing kind on the Zig side
2. mirror it on the Elixir `KindDecl` side
3. regenerate wrapper outputs

That path can unlock standard generated wrappers without building a callback
bridge at all.

This is exactly why callback-heavy exclusions should not be described as a flat
`unsupported_nifs` bucket. Some missing surface area is really "kind surface
not modeled yet", while some is truly "callback bridge still required".

The current `beaver` blocker set is firmly in the second category; updating the
kind surface alone will not emit those APIs.

## How To Formalize This Further

The first formalization step has now landed on the `beaver` side:

- one checked-in manifest in
  [lib/beaver/mlir/capi_kind_manifest.ex](/Users/tsai/oss/beaver/lib/beaver/mlir/capi_kind_manifest.ex:1)
  now drives:
  - Zig kind/resource registration generation for
    [native/src/mlir_capi.zig](/Users/tsai/oss/beaver/native/src/mlir_capi.zig:1)
  - Elixir `KindDecl` emission in
    [lib/beaver/mlir/capi_codegen.ex](/Users/tsai/oss/beaver/lib/beaver/mlir/capi_codegen.ex:1)
  - helper-module generation in
    [lib/beaver/mlir/capi_kinds.ex](/Users/tsai/oss/beaver/lib/beaver/mlir/capi_kinds.ex:1)
- that manifest also made one more important distinction explicit:
  - consumer-defined but Zig-registered external kinds such as `Beaver.Printer`
  - consumer-defined Elixir-only handwritten kinds such as
    `Beaver.MLIR.UnrankedMemRefDescriptor`

The next slice has now landed too, but it is still consumer-biased rather than
framework-complete:

- `Kinda.Wrapper.Extract` now preserves raw C param/return types in
  framework-owned IR
- `Kinda.Wrapper.Generate` now carries those raw C signature facts into
  `Kinda.CodeGen.NIFDecl`
- `Kinda.CodeGen` now emits public `@spec` declarations from that typed IR
- `beaver` is the first downstream to project those C types into remote MLIR
  resource wrapper types

That means the next step is no longer "invent typed IR". It is turning this
consumer-specific projection slice into a reusable framework contract.

Recommended direction:

- keep the consumer kind surface explicit and machine-readable, instead of
  letting it drift back into parallel lists
- classify generated surface entries as:
  - generated Zig/Elixir paired kinds
  - consumer-defined Zig-registered external kinds
  - consumer-defined handwritten Elixir-only kinds
- reserve callback-bridge manifests for blockers whose unblock path is
  callback-runtime work, not kind-surface sync
- generalize the checked-in manifest pattern so downstreams do not have to
  hand-roll their own version of:
  - Zig resource-kind registration generation
  - Elixir `KindDecl` emission
  - handwritten helper-module generation
- generalize the newly-landed typed signature slice so downstreams do not have
  to hand-roll their own projection from:
  - extracted raw C param/return types
  - public wrapper/resource types
  - generated `@spec` declarations
  - future `@opaque` / result-shape contracts

That is the path from today's landed `beaver` slice to a real framework-level
generation contract.

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
- formalize the intermediate representation for names, docs, and raw C
  signature facts

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

At that point, the typed single-source contract should also no longer be
"`beaver` knows how to map MLIR C types". It should be:

- `kinda` owns the typed C signature schema
- downstream policy optionally projects raw C types into richer public wrapper
  types
- codegen/runtime/docs all consume the same typed declaration contract

Without that, the code is merely moved, not generalized.

## Callback-Bridge Generation Blockers

The current `beaver` policy still generation-blocks a small MLIR CAPI subset.

That set should not remain an untyped blacklist forever. The current best
classification is:

- `:callback_bridge_required`

These APIs are special because they are not plain "call a C function and decode
the result" wrappers. They need one or more of:

- callback trampolines from native code into BEAM
- lifetime/ownership contracts
- scheduler-aware invocation metadata
- richer conversion of function-like Elixir inputs

The right future move is:

- keep generic extraction/generation in `kinda`
- keep callback-bridge metadata in `kinda`
- add a later callback-bridge layer in `kinda`
- then retire the old `unsupported_*` compatibility vocabulary completely in
  favor of generation-blocker and callback-bridge terminology

This is intentionally a later phase. It should not block the current split of:

- generic extraction/generation
- consumer-specific policy

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
