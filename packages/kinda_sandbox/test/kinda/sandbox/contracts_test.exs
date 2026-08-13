defmodule Kinda.Sandbox.ContractsTest do
  use ExUnit.Case, async: true

  alias Kinda.Sandbox.{Error, Handle}

  defmodule Backend do
    @behaviour Kinda.Sandbox.Backend

    @impl true
    def capabilities, do: %{}

    @impl true
    def create(:valid, _options), do: {:ok, :backend_handle}

    def create(_spec, _options) do
      {:error, Error.exception(reason: :invalid_spec)}
    end

    @impl true
    def close(:backend_handle), do: :ok
  end

  test "a backend exposes only lifecycle callbacks and a capability map" do
    assert Backend.capabilities() == %{}
    assert Backend.create(:valid, []) == {:ok, :backend_handle}
    assert Backend.close(:backend_handle) == :ok
  end

  test "errors have a closed set of facade reasons" do
    assert {:error, %Error{reason: :invalid_spec}} = Backend.create(:invalid, [])
    assert Exception.message(Error.exception(reason: :disconnected)) == "sandbox is disconnected"
  end

  test "public handles contain only a node-local reference" do
    handle = Handle.new(make_ref())
    assert %Handle{} = handle
    assert Map.keys(Map.from_struct(handle)) == [:ref]
  end
end
