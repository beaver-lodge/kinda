# Kinda Micro-Examples

This directory is the checked-in micro-example lane for `kinda`.

Its job is to prove one narrow framework slice at a time with the smallest
useful runnable artifact.

Today the active micro-example is:

- [`wrapper_reporting.exs`](wrapper_reporting.exs)

Preferred repo-root entry points:

```sh
mix kinda.wrapper.example
mix kinda.wrapper.example --json
mix kinda.wrapper.example --report-only
```

Direct script entry point:

```sh
elixir examples/wrapper_reporting.exs
```

Repo-level umbrella verification:

```sh
mix kinda.verify
```

That umbrella verifier covers:

- root tests
- the micro-example reporting surface
- the bundled `kinda_example` application

This directory is intentionally not the place for end-to-end native-app demos.
Those belong in:

- [`packages/kinda_example/`](../packages/kinda_example/README.md)

The governing plan for that split is:

- [`docs/example-surface-unification-plan.md`](../docs/example-surface-unification-plan.md)
