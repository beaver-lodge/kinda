defmodule Kinda.Sandbox.Backend.LocalProcess do
  @moduledoc """
  Local process lifecycle and working-directory backend.

  Each handle owns one unique child directory and every command started by the
  handle. This is not containment: commands run as the current OS user and may
  access the host filesystem, network, processes, and resources.
  """

  @behaviour Kinda.Sandbox.Backend

  alias Kinda.Sandbox.Backend.LocalProcess.Spec
  alias Kinda.Sandbox.Error

  defmodule State do
    @moduledoc false
    @enforce_keys [:directory, :env]
    defstruct [:directory, :env]
  end

  @impl true
  def capabilities, do: %{command: __MODULE__.Command}

  @impl true
  def create(%Spec{} = spec, _options) do
    with :ok <- validate_spec(spec),
         {:ok, directory} <- create_directory(spec.parent_directory) do
      {:ok, %State{directory: directory, env: spec.env}}
    end
  end

  def create(spec, _options) do
    {:error, invalid_spec("expected a Kinda.Sandbox.Backend.LocalProcess.Spec", spec)}
  end

  @impl true
  def close(%State{directory: directory}) do
    case File.rm_rf(directory) do
      {:ok, _paths} ->
        :ok

      {:error, path, reason} ->
        {:error, filesystem_error("could not remove sandbox", path, reason)}
    end
  end

  defp validate_spec(%Spec{parent_directory: parent, env: env}) do
    cond do
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

  defp create_directory(parent_directory) do
    id = System.unique_integer([:positive, :monotonic])
    parent = Path.expand(parent_directory || System.tmp_dir!())
    directory = Path.join(parent, "kinda-process-#{id}")

    case File.mkdir_p(directory) do
      :ok ->
        {:ok, directory}

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
