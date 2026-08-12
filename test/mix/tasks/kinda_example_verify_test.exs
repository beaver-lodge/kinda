defmodule Mix.Tasks.Kinda.Example.VerifyTest do
  use ExUnit.Case, async: true

  defmodule ExampleVerifierStub do
    def verify(opts \\ []) do
      send(self(), {:example_verify_called, opts})
      :ok
    end
  end

  setup do
    previous = Application.get_env(:kinda, :example_verifier)
    Application.put_env(:kinda, :example_verifier, ExampleVerifierStub)

    on_exit(fn ->
      if previous == nil do
        Application.delete_env(:kinda, :example_verifier)
      else
        Application.put_env(:kinda, :example_verifier, previous)
      end
    end)

    :ok
  end

  test "delegates to the bundled example verifier" do
    Mix.Task.reenable("kinda.example.verify")

    assert :ok = Mix.Task.run("kinda.example.verify")
    assert_received {:example_verify_called, []}
  end
end
