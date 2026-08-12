defmodule Kinda.Testing.SandboxTest do
  use ExUnit.Case, async: true

  alias Kinda.Testing.Sandbox

  test "allocates unique module, entry and output identities" do
    first = Sandbox.new!(__MODULE__)
    second = Sandbox.new!(__MODULE__)
    on_exit(fn -> Sandbox.cleanup(first) end)
    on_exit(fn -> Sandbox.cleanup(second) end)

    refute first.module == second.module
    refute first.entry_name == second.entry_name
    refute first.directory == second.directory
    assert first.entry_name == Atom.to_string(first.module)
  end

  test "requires builders to produce a real library" do
    sandbox = Sandbox.new!(__MODULE__)
    on_exit(fn -> Sandbox.cleanup(sandbox) end)
    library = Path.join(sandbox.directory, "fixture.so")
    File.write!(library, "fixture")

    built =
      Sandbox.build!(sandbox, fn contract ->
        assert contract.entry_name == Atom.to_string(contract.module)
        library
      end)

    assert built.library == Path.expand(library)
  end
end
