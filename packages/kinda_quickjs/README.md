# Kinda QuickJS

An embedded JavaScript runtime built with Kinda. The package pins QuickJS
2026-06-04 and compiles the upstream C sources into the NIF so deployments do
not depend on a system QuickJS installation.

```elixir
Kinda.QuickJS.eval("40 + 2")
#=> 42
```

Persistent runtimes own one or more isolated contexts. Values and promises retain
their originating context, pending jobs are driven explicitly, and ES modules are
loaded only from an application-controlled in-memory registry. Bytecode is bound
to the exact pinned QuickJS release.
