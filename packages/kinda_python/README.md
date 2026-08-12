# Kinda Python

`kinda_python` embeds CPython 3.14 through Kinda. The runtime is supplied by the
host and discovered through Python's own `sysconfig`, so the NIF is always
compiled and linked against the exact interpreter selected on `PATH`.

This first layer owns process-wide initialization. It deliberately never calls
`Py_FinalizeEx`: finalizing CPython from a NIF unload callback is unsafe because
BEAM code, resource destructors, and hot-upgraded NIF generations may still
refer to the runtime.

The package requires a shared CPython 3.14 installation and its development
headers. Isolated interpreter and execution resources are layered in subsequent
stacked changes.
