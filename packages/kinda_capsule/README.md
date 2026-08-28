# Kinda Capsule

`kinda_capsule` is an owner-scoped typed episode runtime built on
`kinda_sandbox`. It turns a Sandbox backend, a trusted task, and a synchronous
verifier into a reset/act/observe/grade lifecycle.

```elixir
{:ok, capsule} = Kinda.Capsule.create(spec)
{:ok, observation} = Kinda.Capsule.reset(capsule, seed: 42)
{:ok, result} = Kinda.Capsule.execute(capsule, command)
{:ok, score} = Kinda.Capsule.grade(capsule)
{:ok, trace} = Kinda.Capsule.trace(capsule)
{:ok, digest} = Kinda.Capsule.Bundle.export(trace, "episode", artifact_sources: sources)
:ok = Kinda.Capsule.close(capsule)
```

## Guarantees

- The creating process owns the Capsule. Owner exit closes active executions,
  task state, and the Sandbox in that order.
- A Capsule accepts one action at a time. Reset and close cancel active work;
  old execution handles become disconnected.
- Reset is replacement, not mutation. Cleanup failure prevents a replacement
  episode from starting. Every successful reset assigns a distinct episode ID
  and binds task, fixture, verifier, runtime, and model identity.
- Task callback crashes and invalid returns fail closed. Declared task errors
  and verifier failures leave a valid current episode available for retry.
- Each accepted terminal command contributes exactly one ordered step, up to
  `max_steps`. Reset clears the in-memory trace.
- Artifacts are digest-addressed manifest entries. Steps, observations, score
  components, and failure modes can link to them through stable evidence refs.
- Exported episode bundles bind their documents and artifacts with SHA-256.
  `Bundle.regrade/3` verifies the bundle plus verifier version/digest before a
  sealed verifier sees the evidence.
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

The command-backed MVP does not promise deterministic replay, snapshots,
cross-node handles, concurrent actions, runtime-selected action adapters, or a
durable event database. Export is an explicit immutable bundle operation, not
automatic persistence. Trace values and telemetry are projections, not a
serialization of backend state.
