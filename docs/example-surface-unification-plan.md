# Kinda Example-Surface Unification Plan

## Summary

`kinda` currently has two different example surfaces:

- `examples/`
- `kinda_example/`

Both are useful. Neither is yet fully formalized as part of one coherent
example strategy.

The right move is not to delete one of them. The right move is to define a
clear example ladder:

1. repo-local micro-examples for narrow framework slices
2. a bundled application example for end-to-end runtime closure

This document formalizes that split and turns it into an evolution plan.

## Why This Plan Exists

Today `kinda` already uses both surfaces in the root verifier:

- [Kinda.RootVerifier](/Users/tsai/oss/kinda/lib/kinda/root_verifier.ex:1)
  runs:
  - root `mix test`
  - `mix kinda.wrapper.example --json`
  - bundled `kinda_example`

That means the repo already treats these surfaces as more than demos.
They are part of the checked-in trust boundary.

What is missing is a formal contract for:

- what each example is supposed to prove
- which surface is authoritative for which framework capability
- how new example work should be added without creating duplication

## Current Surfaces

### 1. `examples/`

Current contents:

- [examples/wrapper_reporting.exs](/Users/tsai/oss/kinda/examples/wrapper_reporting.exs:1)

Current role:

- quickest repo-local proof of the wrapper extraction/reporting pipeline
- runnable without entering a separate Mix project
- mirrored through:
  - [Mix.Tasks.Kinda.Wrapper.Example](/Users/tsai/oss/kinda/lib/mix/tasks/kinda.wrapper.example.ex:1)
  - [Kinda.Wrapper.Example](/Users/tsai/oss/kinda/lib/wrapper/example.ex:1)

What this surface is good at:

- framework-owned manifest extraction
- policy application
- callback-bridge report rendering
- JSON/human-readable output smoke

What this surface is not good at:

- NIF build and load closure
- end-to-end ElixirMake integration
- resource kind runtime behaviour under a real app

### 2. `kinda_example/`

Current contents:

- [kinda_example/README.md](/Users/tsai/oss/kinda/kinda_example/README.md:1)
- [kinda_example/mix.exs](/Users/tsai/oss/kinda/kinda_example/mix.exs:1)
- [kinda_example/build.zig](/Users/tsai/oss/kinda/kinda_example/build.zig:1)
- [kinda_example/lib/kinda_example_nif.ex](/Users/tsai/oss/kinda/kinda_example/lib/kinda_example_nif.ex:1)
- [kinda_example/lib/kinda_example_native.ex](/Users/tsai/oss/kinda/kinda_example/lib/kinda_example_native.ex:1)
- [kinda_example/lib/kinda_example_code_gen.ex](/Users/tsai/oss/kinda/kinda_example/lib/kinda_example_code_gen.ex:1)
- [kinda_example/test/kinda_example_test.exs](/Users/tsai/oss/kinda/kinda_example/test/kinda_example_test.exs:1)

Current role:

- bundled end-to-end example app for:
  - `Kinda.ResourceKind`
  - `Kinda.CodeGen`
  - native build integration
  - resource wrapping and term conversion

What this surface is good at:

- proving a real native app still loads
- proving generated and handwritten runtime pieces cooperate
- exercising repo-local verification under:
  - [Kinda.ExampleVerifier](/Users/tsai/oss/kinda/lib/kinda/example_verifier.ex:1)

What this surface is not good at:

- quickly demonstrating narrow wrapper/reporting framework slices
- scaling to many tiny independent framework examples

## The Current Problem

The current split works operationally, but it is underdefined.

The main issues are:

- naming does not yet communicate the example hierarchy
  - `examples/` looks generic
  - `kinda_example/` looks like an old one-off demo
- docs do not clearly say which surface is canonical for which capability
- there is no formal intake rule for future examples
  - should a new proof live in `examples/` or `kinda_example/`?
- verification already treats both surfaces as first-class, but documentation
  does not yet mirror that reality

Without a formal plan, future example work will drift into one of two bad
patterns:

1. everything gets shoved into `kinda_example/`, making it bloated
2. many tiny scripts appear under `examples/` with no stable contract

## Recommended Unified Model

`kinda` should explicitly define an example ladder.

### Layer A. Micro-examples

Location:

- `examples/`

Purpose:

- prove one narrow framework slice with the smallest runnable artifact

Expected shape:

- one script or one task-backed script per example
- no private project-local build system unless the example truly needs it
- focused on framework semantics, not product polish

Good fits:

- wrapper manifest extraction
- callback-bridge reporting
- scheduler-metadata rendering
- codegen/spec/doc emission smoke

### Layer B. Bundled app example

Location:

- `kinda_example/`

Purpose:

- prove full app-level runtime closure for the core framework

Expected shape:

- real Mix project
- real native build
- real tests
- canonical example for:
  - resource kinds
  - generated NIF declarations
  - runtime forwarding/normalization
  - native load/load-error behaviour

Good fits:

- end-to-end NIF build/load
- resource conversion contracts
- forwarder/runtime examples
- integration with root verification

### Unification Rule

The two surfaces should be documented and evolved as one program:

- `examples/` proves isolated framework slices
- `kinda_example/` proves integrated framework closure

New example work should be added according to this rule:

- if the goal is a narrow framework proof, it belongs in `examples/`
- if the goal is an end-to-end runtime proof, it belongs in `kinda_example/`
- if both are needed, add:
  - a micro-example first
  - then a bundled-app integration slice only if the capability needs runtime
    closure

## Formal Repository Contract

After this plan lands, the intended contract is:

- `mix kinda.wrapper.example`
  is the shortest stable proof of the wrapper/reporting framework surface
- `mix kinda.verify`
  is the canonical repo-level verifier for:
  - root tests
  - micro-example reporting
  - bundled app example closure
- `kinda_example/`
  is not a detached demo
  - it is the checked-in bundled application example
- `examples/`
  is not a dumping ground
  - it is the checked-in micro-example lane

## Evolution Phases

### Phase 1. Documentation and naming formalization

Goal: make the example hierarchy explicit before restructuring files.

- add this plan
- reference it from:
  - [rustler-gap-roadmap.md](/Users/tsai/oss/kinda/docs/rustler-gap-roadmap.md:1)
- update docs so that:
  - `examples/` is described as the micro-example lane
  - `kinda_example/` is described as the bundled app example

Status:

- this phase is what the current document lands

### Phase 2. Shared example contract

Goal: remove ambiguity between example surfaces.

- define a standard README template for every future example surface:
  - what it proves
  - how to run it
  - which verifier path covers it
- keep `mix kinda.verify` as the root umbrella verifier
- ensure every example surface has one clearly named entry point

Exit criteria:

- no example surface exists without a declared verifier path
- no example surface exists without a declared capability target

### Phase 3. Reduce duplication between surfaces

Goal: share semantics while keeping two different closure levels.

- move shared helper wording and verification guidance into common docs
- align naming between:
  - `Kinda.Wrapper.Example`
  - `Kinda.ExampleVerifier`
  - `Kinda.RootVerifier`
- make it obvious which example is:
  - framework-output-oriented
  - runtime-app-oriented

Possible follow-up:

- add a second micro-example if scheduler metadata or richer conversion APIs
  become first-class

### Phase 4. Graduate `kinda_example/` into the canonical medium example

Goal: make the bundled app the real proof point for Rustler-like completeness.

- grow `kinda_example/` only along capabilities that require integrated native
  closure
- keep it medium-sized and framework-representative
- do not let it absorb every small feature proof

Target scope:

- resource kinds
- forwarder/runtime semantics
- generated NIF declarations
- load/reload behaviour as the framework grows

### Phase 5. Optional physical re-layout

Goal: align directory names with the formalized model, but only if the value is
worth the churn.

Possible future layout:

- `examples/` for micro-examples
- `examples/apps/kinda_example/` or similar for bundled app examples

This is intentionally not required yet.

The immediate need is conceptual unification, not filesystem churn.

## What Should Happen Next

The next example-related work in `kinda` should follow this order:

1. keep this plan as the source of truth
2. reference it anywhere the roadmap talks about docs/examples completeness
3. only add new example code after deciding whether it is:
   - a micro-example
   - a bundled app example slice
4. when Rustler-gap work lands in:
   - scheduler metadata
   - runtime API completeness
   - prebuilt distribution
   decide explicitly whether the first proof belongs in:
   - `examples/`
   - `kinda_example/`
   - both

## Bottom Line

`examples/` and `kinda_example/` should not compete.

They should form one deliberate example program:

- `examples/` for narrow framework proofs
- `kinda_example/` for integrated native-app closure

That is the formal shape `kinda` needs if it wants examples to behave like a
real product surface instead of a mix of scripts and historical demos.
