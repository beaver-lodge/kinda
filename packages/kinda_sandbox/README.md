# Kinda Sandbox

`kinda_sandbox` defines backend-neutral lifecycle and capability contracts for
isolated execution environments. It is an independent Mix project and does not
depend on the root `kinda` package or on Zig.

The facade deliberately resembles the useful part of Ecto's adapter model: the
caller holds one stable public handle while backend state remains private. It
does not introduce a global Repo-like name, pooling, or a universal template.

## Local native builds

The initial backend allocates a unique BEAM module, NIF entry name, and owned
child directory. The builder is an MFA and receives the neutral build context
as its final argument:

```elixir
alias Kinda.Sandbox
alias Kinda.Sandbox.Backend.LocalNative
alias Kinda.Sandbox.Backend.LocalNative.Spec
alias Kinda.Sandbox.NativeBuild

{:ok, sandbox} =
  Sandbox.create(
    LocalNative,
    %Spec{base_module: MyApp.NativeFixture, env: %{"CC" => "zig cc"}}
  )

{:ok, library} = NativeBuild.build(sandbox, {MyBuilder, :build, [:release]})
:ok = Sandbox.close(sandbox)
```

The builder function above has an effective arity of two:

```elixir
def build(profile, context) do
  # context.module, context.entry_name, context.directory, context.env
  # Compile into context.directory and return the artifact path.
end
```

The artifact must be a regular file lexically inside the owned child directory.
A failed build clears partial contents and leaves the handle available for a
retry. Closing removes only the child, never a supplied parent directory.

## Ownership and capabilities

The creating process owns the sandbox by default. `transfer_owner/2` moves that
responsibility to another live process, while `detach/1` makes lifetime fully
explicit. Owner exit and normal handle-server termination close the backend.
`close/1` is idempotent.

`capabilities/1` reports capability keys such as `:native_build`. Operations use
typed facades such as `Kinda.Sandbox.NativeBuild`; unsupported operations return
a normalized `:unsupported_capability` error. An untrappable forced kill cannot
promise generic cleanup: afterward `close/1` remains `:ok`, while other calls
return `:disconnected`.

Future command, filesystem, container, and remote-provider features should be
introduced as typed capabilities only when a concrete backend requires them.
