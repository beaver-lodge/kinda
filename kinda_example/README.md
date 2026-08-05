# KindaExample

This is the bundled application example for `kinda`.

It exists to prove end-to-end runtime closure for:

- `Kinda.ResourceKind`
- `Kinda.CodeGen`
- native build/load integration
- resource wrapping and term conversion

Preferred repo-root entry point:

```sh
mix kinda.example.verify
```

Repo-level umbrella verifier:

```sh
mix kinda.verify
```

That keeps the bundled app inside the same verifier surface as the main repo,
instead of treating it as a detached demo.

You can still run it directly from `kinda_example/`:

```sh
cd kinda_example
mix test --force
```

The companion plan that formalizes the split between:

- `examples/`
- `kinda_example/`

is:

- [example-surface-unification-plan.md](/Users/tsai/oss/kinda/docs/example-surface-unification-plan.md:1)
