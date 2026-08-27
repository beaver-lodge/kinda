# Kinda Capsule

`kinda_capsule` is an owner-scoped typed episode runtime built on
`kinda_sandbox`. It turns a Sandbox backend, a trusted task, and a synchronous
verifier into a reset/act/observe/grade lifecycle.

```elixir
{:ok, capsule} = Kinda.Capsule.create(spec)
{:ok, observation} = Kinda.Capsule.reset(capsule, seed: 42)
{:ok, result} = Kinda.Capsule.execute(capsule, command)
{:ok, score} = Kinda.Capsule.grade(capsule)
:ok = Kinda.Capsule.close(capsule)
```

## Guarantees

- The creating process owns the Capsule. Owner exit closes active executions,
  task state, and the Sandbox in that order.
- A Capsule accepts one action at a time. Reset and close cancel active work;
  old execution handles become disconnected.
- Reset is replacement, not mutation. Cleanup failure prevents a replacement
  episode from starting.
- Task callback crashes and invalid returns fail closed. Declared task errors
  and verifier failures leave a valid current episode available for retry.
- Each accepted terminal command contributes exactly one ordered step, up to
  `max_steps`. Reset clears the in-memory trace.
- Command traces retain executable/argv/cwd, environment key names, stdin byte
  count, bounded output, termination, timing, truncation flags, and explicit
  action metadata. They do not retain environment values, stdin contents,
  backend-private metadata, or Sandbox handles.
- Telemetry under `[:kinda, :capsule, operation]` contains lifecycle facts and
  byte counts, never episode seeds, command payloads, output, or callback data.

## Trust boundary and non-goals

Task and verifier modules are trusted host code. Sandbox backends define the
actual containment boundary; Capsule itself is lifecycle orchestration, not a
security sandbox.

The command-backed MVP does not promise durable traces, deterministic replay,
snapshots, artifacts, cross-node handles, concurrent actions, runtime-selected
action adapters, or language/database-specific actions. Trace values and
telemetry are projections, not a serialization of backend state.
