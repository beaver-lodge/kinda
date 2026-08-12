# Kinda QuickJS

An embedded JavaScript runtime built with Kinda. The package pins QuickJS
2026-06-04 and compiles the upstream C sources into the NIF so deployments do
not depend on a system QuickJS installation.

```elixir
Kinda.QuickJS.eval("40 + 2")
#=> 42
```
