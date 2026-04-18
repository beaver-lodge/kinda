# Kinda Rustler-Gap Roadmap

## Summary

`kinda` already has one genuinely strong idea:

- Zig comptime-generated resource kinds for consuming large C APIs

That idea is good enough that `beaver` has built a large MLIR boundary on top
of it. But `kinda` is still much closer to a powerful substrate than to a
Rustler-like completed product.

The gap is not mainly about raw capability. The gap is about productization:

- public API shape
- runtime semantics
- scheduler policy
- release/distribution flow
- testing and documentation

The example/docs track now also has a dedicated companion plan:

- [example-surface-unification-plan.md](/Users/tsai/oss/kinda/docs/example-surface-unification-plan.md:1)

The runtime/ref-wrap track now also has a dedicated companion plan:

- [nif-ref-runtime-surface-plan.md](/Users/tsai/oss/kinda/docs/nif-ref-runtime-surface-plan.md:1)

## Current State

### What Kinda clearly already has

- `ResourceKind` for opaque/resource-backed native values
  - [lib/resource_kind.ex](/Users/tsai/oss/kinda/lib/resource_kind.ex:1)
  - [src/kinda.zig](/Users/tsai/oss/kinda/src/kinda.zig:33)
- generated NIF declarations via `Kinda.CodeGen`
  - [lib/kinda_codegen.ex](/Users/tsai/oss/kinda/lib/kinda_codegen.ex:1)
- low-level BEAM term conversion helpers in Zig
  - [src/beam.zig](/Users/tsai/oss/kinda/src/beam.zig:328)
  - [src/beam.zig](/Users/tsai/oss/kinda/src/beam.zig:894)
- a minimal ElixirMake precompiler target resolver
  - [lib/zig_precompiler.ex](/Users/tsai/oss/kinda/lib/zig_precompiler.ex:1)

### What the current codebase also reveals

- the Elixir public API is very small
- tests are minimal
  - [test/kinda_test.exs](/Users/tsai/oss/kinda/test/kinda_test.exs:1)
- the example app is useful but tiny
  - [kinda_example/lib/kinda_example_nif.ex](/Users/tsai/oss/kinda/kinda_example/lib/kinda_example_nif.ex:1)
- several ideas are documented before they are fully shipped
  - README references `Kinda.Prebuilt`
  - actual code only contains [lib/prebuilt_meta.ex](/Users/tsai/oss/kinda/lib/prebuilt_meta.ex:1)

That is a normal prototype shape, but it is not yet a Rustler-like library
shape.

## What "Rustler-like Complete" Means Here

`kinda` should not copy Rustler mechanically. It has a different thesis:

- Rustler is centered on Rust + typed encoder/decoder ergonomics
- Kinda is centered on Zig + generated resource-kind wrappers for C libraries

But if `kinda` wants to feel as complete as Rustler, it needs to become
comparable along the following axes:

1. Declarative NIF definition
2. Predictable term/resource conversion
3. Explicit scheduler policy
4. Stable lifecycle hooks
5. First-class precompiled distribution
6. Strong docs/examples/tests

## Main Gaps Versus Rustler

### 1. Public API ergonomics

Rustler gives users a clear top-level experience:

- `rustler::init!`
- `#[rustler::nif]`
- `rustler::resource!`
- `Encoder` / `Decoder`

Official docs describe simplified NIF declaration, resource setup, and
per-function scheduler metadata:

- Rustler changelog:
  https://hexdocs.pm/rustler/changelog.html
- Rustler upgrade guide:
  https://hexdocs.pm/rustler/upgrade.html

By contrast, `kinda` currently exposes mostly primitives:

- `use Kinda.ResourceKind`
- `use Kinda.CodeGen`
- a first public `Kinda.Forwarder` runtime slice:
  - `check!/1`
  - `raw_call/3`
  - `call/3`
  - `forward/3`
  - `invoke_kind_nif/5`
  - `to_term/1`
- and generated public wrappers now route through an explicit runtime helper
  instead of each wrapper hand-rolling unwrap + raw invoke + `check!/1`
- and generated public wrappers now also have a first companion raw module
  surface (`RootModule.Raw`)
- and kind-scoped runtime raw calls now prefer that companion raw surface too
- and the first downstream handwritten kind-call path now routes through that
  same framework helper instead of direct `apply(CAPI, ...)`
- and the wrapper-policy pipeline now preserves per-variant dirty scheduler
  metadata in framework-owned `NIFDecl` IR instead of only encoding it in Zig
  entry strings
- and classic `use Kinda.CodeGen` modules now expose their generated
  declaration manifest through `__kinda_nif_decls__/0`
- and `use Kinda.CodeGen` modules now also expose a machine-readable typed
  signature surface through `__kinda_signature_manifest__/0`, whether it comes
  directly from `signature_manifest/0` or is derived from the canonical
  declaration contract
- and the wrapper/extraction pipeline now preserves raw C parameter/return
  types in framework-owned IR:
  - `Kinda.Wrapper.Function`
  - `Kinda.CodeGen.NIFDecl`
- and the same manifest now also preserves named C record declarations and
  fields through:
  - `Kinda.Wrapper.CRecord`
  - `Kinda.Wrapper.CField`
- and consumer policy can now project those raw C signature facts into
  generated public `@spec` declarations and machine-readable record contracts
  instead of leaving the Elixir surface purely name-driven
- and `Kinda.Wrapper.Generate.declaration_manifest_struct/2` now exposes the
  canonical framework-owned declaration contract for that typed wrapper surface
- and `Kinda.Wrapper.Generate.declaration_manifest/2` now serializes that same
  contract into a JSON-friendly machine-readable form
- and `Kinda.Wrapper.Generate.signature_manifest/2` now acts as a derived
  compatibility view over that canonical declaration contract instead of being
  the primary wrapper-side source
- and that contract can now also be surfaced on generated modules instead of
  only living as a detached build artifact

This is real progress, but the runtime surface is still too thin for the full
set of `beaver`-style adapter needs.

#### Needed evolution

- Add a real top-level library module such as `Kinda.Library`
- Make NIF declaration metadata first-class, not hidden in manual codegen lists
- Generalize the first manifest-backed consumer slice that `beaver` has now
  landed: one checked-in contract driving Zig registration generation, Elixir
  `KindDecl` emission, and handwritten consumer-defined entries from one source
- Lift that consumer contract into a reusable `kinda` surface so pure
  handle-like CAPI additions stop looking like ad hoc "unsupported" gaps
- Generate docs/specs/names from declarations
- Replace the remaining ad hoc handwritten raw-export conventions with explicit
  public APIs

### 2. Conversion model

Rustler's practical strength is not just raw NIF support. It is the existence
of a coherent typed conversion model: decoded arguments, encoded results, and
well-defined resource behavior.

`kinda` does have low-level conversion helpers in Zig, but the consumer-facing
surface is still mostly:

- unwrap refs
- fetch resources
- make resources
- manually postprocess return tuples

This is exactly why `beaver` had to grow a substantial adapter layer in
[lib/beaver/native.ex](/Users/tsai/oss/beaver/lib/beaver/native.ex:1).

The first typespec-driven conversion slice has also now landed:

- `Kinda.Wrapper.Extract` captures raw C param/return types as
  `Kinda.Wrapper.CType`
- `Kinda.Wrapper.Extract` also captures named C record declarations and fields
- `Kinda.Wrapper.Generate` preserves those facts into generated `NIFDecl`
  metadata
- `Kinda.CodeGen` now emits `@spec` declarations when that typed metadata is
  present
- `Kinda.Wrapper.Generate.signature_manifest/2` now also projects record fields
  into public typespecs and emits record-level public map types
- `Kinda.Wrapper.Generate.declaration_manifest_struct/2` now materializes the
  canonical framework-owned declaration contract for that typed slice
- `Kinda.Wrapper.Generate.declaration_manifest/2` now makes the same typed
  slice available as a JSON-friendly contract for CI/build consumers
- `Kinda.Wrapper.Generate.signature_manifest/2` now derives its compatibility
  view from that canonical declaration contract
- `Kinda.CodeGen.DeclarationManifest.build/2` now also owns the derivation of
  generated `TypeDecl` metadata from that typed declaration contract, so
  type-alias generation no longer depends on a signature-only source path
- `Kinda.CodeGen` can now consume that same manifest contract and emit
  deterministic public record type aliases on generated modules
- those generated aliases use atom field keys derived from extracted C field
  names, while the underlying manifest remains string-keyed and
  machine-readable
- `Kinda.CodeGen` now also exposes a formal `TypeDecl` metadata surface through
  `__kinda_type_decls__/0`, so generated public types are not only observable
  via emitted AST or BEAM abstract code
- `Kinda.CodeGen` now also exposes a unified declaration contract through
  `__kinda_declaration_manifest__/0`, so generated function/type declarations
  are no longer split across ad hoc module probes
- `Kinda.Wrapper.Generate.declaration_manifest/2` now exports the same unified
  declaration surface as a JSON-friendly machine-readable contract
- `Kinda.CodeGen` can now also ingest `declaration_manifest/0` as a direct
  generation source, so checked-in declaration sidecars can drive module
  generation instead of only mirroring it after the fact, while kind-derived
  helper NIFs still come from the explicit kind surface
- and the final file-backed declaration loading interface now lives in
  `Kinda.CodeGen.DeclarationManifest.load!/1`, so downstreams do not have to
  hand-roll `File.read!/Code.eval_string/JSON.decode!` adapters
- and `Kinda.CodeGen.source_declaration_manifest/1` /
  `Kinda.CodeGen.declaration_surfaces/2` now formalize the distinction between
  the checked-in declaration source and the final generated declaration
  surfaces, so downstreams do not have to guess when `nif_name`
  canonicalization, kind-helper merging, and `TypeDecl` materialization happen
- and that resolved layer is now itself a framework-owned IR through
  `Kinda.CodeGen.DeclarationSurfaces`, rather than a bare internal map shape
- and generated modules now expose that same resolved IR through
  `__kinda_declaration_surfaces__/0`, so downstreams can consume the formalized
  declaration surface directly instead of reassembling it from split metadata
- when a declaration manifest is present, the typed signature surface is now a
  derived view over its embedded `signature_manifest`, rather than a required
  parallel build/source artifact
- and when a module exposes both `signature_manifest/0` and
  `declaration_manifest/0`, the declaration manifest is now the canonical
  source of the generated signature surface
- and declaration-manifest-backed generators no longer need a parallel
  `nifs()/0` callback just to satisfy the framework; only the explicit kind
  surface still remains outside the declaration contract
- `beaver` now acts as the first consumer probe by mapping MLIR handle-like
  C types, including `struct Mlir...` field spellings inside records, to public
  remote wrapper types

#### Needed evolution

- Define a public wrap/unwrap protocol or behaviour layer
- Distinguish resource ownership modes more explicitly:
  - owned resource
  - borrowed pointer
  - mutable array
  - opaque pointer
- Add standard conversions for common BEAM-facing shapes:
  - binaries
  - iolists
  - tuples
  - maps
  - tagged error tuples
- Generalize the new typespec-driven projection slice from the first
  consumer-specific MLIR mapping into a stable framework contract for C
  pointers, pointer-arrays, enums, and common result shapes
- Generate `@opaque` / `@type` / `@spec` more systematically from that typed
  contract, especially beyond the first generated record aliases, `TypeDecl`
  metadata, and unified declaration manifest that now land on
  `use Kinda.CodeGen` modules

### 3. Scheduler strategy

Rustler exposes per-NIF scheduling where the NIF is declared.

`kinda` already has the low-level mechanism for NIF flags:

- [src/kinda.zig](/Users/tsai/oss/kinda/src/kinda.zig:334)
- [src/result.zig](/Users/tsai/oss/kinda/src/result.zig:11)

The framework has now landed a first scheduler-metadata slice:

- [lib/codegen/nif_decl.ex](/Users/tsai/oss/kinda/lib/codegen/nif_decl.ex:1)
  carries a real `dirty` field
- [lib/wrapper/policy.ex](/Users/tsai/oss/kinda/lib/wrapper/policy.ex:1)
  exposes a `dirty/1` callback
- [lib/wrapper/generate.ex](/Users/tsai/oss/kinda/lib/wrapper/generate.ex:1)
  preserves that metadata in generated `NIFDecl` manifests
- [lib/kinda_codegen.ex](/Users/tsai/oss/kinda/lib/kinda_codegen.ex:1)
  now exposes those generated declarations on the public module surface via
  `__kinda_nif_decls__/0`

But the current Elixir-facing codegen still does not make scheduling a full
first-class user feature end to end.

That is the exact kind of gap a Rustler-like framework should close.

#### Needed evolution

- Extend the new `NIFDecl.dirty` metadata into a full public declaration
  surface
- Allow per-NIF `:normal | :dirty_cpu | :dirty_io | :auto`
- Generate dual wrappers when auto-routing is needed
- Provide consumer guidance for thresholds and callback safety

### 4. Lifecycle completeness

In `beaver`, the Zig entrypoint still handles resource registration directly:

- [native/src/main.zig](/Users/tsai/oss/beaver/native/src/main.zig:1)

And even there:

- `reload = null`
- `upgrade = null`
- `unload = null`

That is enough for many packages, but not enough for a library that wants to be
an ecosystem-grade native framework.

#### Needed evolution

- Public load/reload/upgrade/unload hooks
- Resource registration helpers with explicit lifecycle semantics
- Background/owned environment helpers for async callbacks and sends
- Clear guidance around safe callback execution and teardown

### 5. Precompiled distribution

RustlerPrecompiled has a documented checksum-based distribution flow:

- https://hexdocs.pm/rustler_precompiled/precompilation_guide.html

`kinda` currently has:

- target detection and compile-time integration
- README references to prebuilt mode
- no fully realized `Kinda.Prebuilt` module
- no checksum/download/release task surface comparable to RustlerPrecompiled

#### Needed evolution

- Implement a real `Kinda.Prebuilt`
- Support checksum files and verified downloads
- Document a supported release workflow
- Broaden target coverage
- Separate "framework capability" from "consumer-specific glue"

### 6. Verification and docs

Rustler feels complete partly because its mental model is stable and well
documented.

`kinda` currently has:

- minimal tests
- minimal example docs
- README-level claims that outrun the shipped API
- a first explicit repo-root entry point split between:
  - `mix kinda.wrapper.example`
  - `mix kinda.example.verify`
- the wrapper micro-example lane now also renders dirty scheduler metadata in
  its generated Elixir manifest output
- real green repo-level verification for that split on the active Zig `0.16`
  line via:
  - `mix kinda.verify`

#### Needed evolution

- Formalize `examples/` and `kinda_example/` as one coherent example program
  via:
  - [example-surface-unification-plan.md](/Users/tsai/oss/kinda/docs/example-surface-unification-plan.md:1)
- Add real integration tests, not just doctests
- Add matrix tests for:
  - resources
  - arrays/pointers
  - dirty schedulers
  - callbacks
  - precompiled loading
- Add at least one medium-complexity example beyond `kinda_example`
- Keep README strictly aligned with shipped modules

## Beaver-As-Probe Assessment

`beaver` is already the best external probe for `kinda` because it stresses:

- a huge generated C API surface
- handwritten and generated NIFs together
- dirty scheduler needs
- callback-heavy flows
- precompiled artifact delivery
- many opaque resource kinds

That means `kinda` should evolve with `beaver` as its primary proving ground,
not with the current tiny example app as its main success criterion.

## Recommended Roadmap

### Phase 1. Productize the public API

Goal: make `kinda` feel like a framework, not just a substrate.

- Add real `Kinda.Library`
- Add real `Kinda.Prebuilt`
- Continue growing `Kinda.Forwarder` from the first public runtime slice into
  a fuller behaviour/API
- Continue extending `NIFDecl` from the newly-landed typed C signature slice
  into a stable declaration contract with names, docs, scheduler flags, typed
  params, and typed returns

### Phase 2. Stabilize conversion semantics

Goal: reduce consumer-specific adapter code.

- Formalize resource wrapper contracts
- Add common term conversion helpers as public APIs
- Lift the current consumer-projected C signature facts into richer framework
  typespec and opaque-type generation
- Provide standard error-shape helpers

### Phase 3. Scheduler-aware NIF declaration

Goal: make dirty scheduling a declaration-time property.

- support dirty CPU / dirty IO metadata
- support auto-routing helpers
- document scheduler policy and callback constraints

### Phase 4. Complete the prebuilt story

Goal: make precompiled distribution a first-class feature.

- implement verified downloads
- add checksum generation and docs
- expand target matrix
- publish a release workflow template

### Phase 5. Verification and docs

Goal: reach Rustler-like trust, not just Rustler-like cleverness.

- Formalize one example ladder across:
  - `examples/`
  - `kinda_example/`
- add real integration tests
- add CI matrix for OTP / Zig / targets
- add at least one large example
- remove README claims that are not yet shipped

## Concrete Near-Term Backlog

If the goal is to move `kinda` materially closer to Rustler in the next few
iterations, the highest-value order is:

1. Ship `Kinda.Prebuilt` for real
2. Extend the newly-landed scheduler metadata in `NIFDecl` into full codegen
   and runtime support
3. Promote the new `RootModule.Raw` surface from companion compatibility layer
   to the stable primary raw contract across generated and handwritten
   kind-call surfaces, instead of keeping root raw stubs as the long-term
   public raw story
4. Add integration tests that exercise `beaver`-style resource flows
5. Turn the newly-landed typed C signature slice into a reusable framework
   contract, then generate stronger Elixir-side types/specs/docs from it

## Bottom Line

`kinda` does not need to become Rustler-in-Zig.

It should become:

- as dependable as Rustler
- while remaining specialized for generated C-library bindings and
  resource-kind-centric native interop

The design thesis is already strong enough. The missing work is mostly the
framework layer that turns a strong thesis into a trustworthy library.
