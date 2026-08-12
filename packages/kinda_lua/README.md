# Kinda Lua

An embedded, multi-instance Lua runtime built with Kinda. The package pins Lua
5.4.8 and compiles the upstream C sources into the NIF so deployments do not
depend on a system Lua installation.

```elixir
Kinda.Lua.eval("return 40 + 2")
#=> 42
```
