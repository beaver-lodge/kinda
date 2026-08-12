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

`Kinda.Python.eval_async/1` uses a linked BEAM task and dirty I/O NIF execution.
Each execution owns an ephemeral OWN_GIL interpreter on one native thread, so
independent executions may run simultaneously without migrating thread state.

## Runtime profiles

The same source supports both official CPython 3.14 profiles:

- regular `3.14`, where persistent isolated interpreters use an independent GIL;
- free-threaded `3.14t`, detected at compile time through `Py_GIL_DISABLED`.

The free-threaded profile is an explicit capability, not an assumption about
imported extensions. Extensions must use multi-phase initialization, support
subinterpreters, and declare that they do not require the GIL. Importing an
extension that silently re-enables the GIL falls outside this package's
free-threaded guarantee.

Persistent interpreter handles serialize access because their `PyThreadState`
must not migrate between concurrent native calls. The async API instead creates,
runs, and destroys an isolated interpreter within one dirty scheduler call;
that invariant is tested with concurrent CPU-bound executions.
