# Kinda Lua

An embedded, multi-instance Lua runtime built with Kinda. The package pins Lua
5.4.8 and compiles the upstream C sources into the NIF so deployments do not
depend on a system Lua installation.

```elixir
Kinda.Lua.eval("return 40 + 2")
#=> 42
```

Persistent VMs isolate globals and serialize access to a single Lua state.
Coroutines and full userdata retain their parent VM, while bytecode is explicitly
bound to Lua 5.4.8. All resources support explicit close and arbitrary BEAM GC
ordering.
