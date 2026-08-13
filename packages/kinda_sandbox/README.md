# Kinda Sandbox

`kinda_sandbox` defines backend-neutral lifecycle and capability contracts for
isolated execution environments. It is an independent Mix project and does not
depend on the root `kinda` package or on Zig.

The first concrete backend is developed separately so the public contract can
remain useful to future local, container, and remote backends.
