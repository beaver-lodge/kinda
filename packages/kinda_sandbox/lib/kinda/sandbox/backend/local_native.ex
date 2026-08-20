defmodule Kinda.Sandbox.Backend.LocalNative do
  @moduledoc """
  Local filesystem and process backend for native development workflows.

  Each handle owns exactly one unique child directory. Closing a handle removes
  that child and never removes the caller-provided parent directory.

  This backend is not a security boundary for untrusted code. Commands run as
  the current OS user and may access the network, paths outside the owned
  directory, other permitted processes, and unrestricted host resources.
  """

  @behaviour Kinda.Sandbox.Backend

  alias Kinda.Sandbox.Backend.LocalNative.Spec
  alias Kinda.Sandbox.Capability.NativeBuild.Context
  alias Kinda.Sandbox.Error

  defmodule State do
    @moduledoc false
    @enforce_keys [:context]
    defstruct [:context]
  end

  @impl true
  def capabilities, do: %{command: __MODULE__.Command, native_build: __MODULE__.NativeBuild}

  @impl true
  def create(%Spec{} = spec, _options) do
    with :ok <- validate_spec(spec),
         {:ok, context} <- create_context(spec) do
      {:ok, %State{context: context}}
    end
  end

  def create(spec, _options) do
    {:error, invalid_spec("expected a Kinda.Sandbox.Backend.LocalNative.Spec", spec)}
  end

  @impl true
  def close(%State{context: %Context{directory: directory}}) do
    case File.rm_rf(directory) do
      {:ok, _paths} ->
        :ok

      {:error, path, reason} ->
        {:error, filesystem_error("could not remove sandbox", path, reason)}
    end
  end

  defp validate_spec(%Spec{base_module: base_module, parent_directory: parent, env: env}) do
    cond do
      not is_atom(base_module) ->
        {:error, invalid_spec("base_module must be a module", base_module)}

      not (is_nil(parent) or is_binary(parent)) ->
        {:error, invalid_spec("parent_directory must be a path", parent)}

      not valid_env?(env) ->
        {:error, invalid_spec("env must contain binary keys and values", env)}

      true ->
        :ok
    end
  end

  defp valid_env?(env) when is_map(env) do
    Enum.all?(env, fn {key, value} -> is_binary(key) and is_binary(value) end)
  end

  defp valid_env?(_env), do: false

  defp create_context(spec) do
    id = System.unique_integer([:positive, :monotonic])
    module = Module.concat(spec.base_module, "Sandbox#{id}")
    parent = Path.expand(spec.parent_directory || System.tmp_dir!())
    directory = Path.join(parent, "kinda-sandbox-#{id}")

    case File.mkdir_p(directory) do
      :ok ->
        {:ok,
         %Context{
           module: module,
           entry_name: Atom.to_string(module),
           directory: directory,
           env: spec.env
         }}

      {:error, reason} ->
        {:error, filesystem_error("could not create sandbox", directory, reason)}
    end
  end

  defp invalid_spec(message, details) do
    Error.exception(
      reason: :invalid_spec,
      backend: __MODULE__,
      operation: :create,
      message: message,
      details: details
    )
  end

  defp filesystem_error(message, path, reason) do
    Error.exception(
      reason: :backend_failure,
      backend: __MODULE__,
      operation: if(message == "could not create sandbox", do: :create, else: :close),
      message: message,
      cause: reason,
      details: %{path: path}
    )
  end
end
