defmodule Kinda.Sandbox.Backend.LocalNative.NativeBuild do
  @moduledoc false

  @behaviour Kinda.Sandbox.Capability.NativeBuild

  alias Kinda.Sandbox.Backend.LocalNative.State
  alias Kinda.Sandbox.Capability.NativeBuild.Context
  alias Kinda.Sandbox.Error

  @impl true
  def build(%State{context: context}, {module, function, arguments} = builder_mfa)
      when is_atom(module) and is_atom(function) and is_list(arguments) do
    result = invoke_builder(module, function, arguments, context)

    case validate_result(result, context) do
      {:ok, artifact} -> {:ok, artifact}
      {:error, %Error{} = error} -> clean_after_failure(context, error, builder_mfa)
    end
  end

  def build(%State{context: context}, builder_mfa) do
    error =
      Error.exception(
        reason: :invalid_spec,
        backend: Kinda.Sandbox.Backend.LocalNative,
        operation: :native_build,
        message: "builder must be a {module, function, arguments} tuple",
        details: builder_mfa
      )

    clean_after_failure(context, error, builder_mfa)
  end

  defp invoke_builder(module, function, arguments, context) do
    apply(module, function, arguments ++ [context])
  catch
    kind, reason -> {:builder_caught, kind, reason, __STACKTRACE__}
  end

  defp validate_result({:ok, path}, context) when is_binary(path),
    do: validate_path(path, context)

  defp validate_result(path, context) when is_binary(path), do: validate_path(path, context)
  defp validate_result({:error, %Error{} = error}, _context), do: {:error, error}

  defp validate_result(other, _context) do
    {:error,
     Error.exception(
       reason: :backend_failure,
       backend: Kinda.Sandbox.Backend.LocalNative,
       operation: :native_build,
       message: "native builder returned an invalid result",
       details: other
     )}
  end

  defp validate_path(path, %Context{directory: directory}) do
    artifact = Path.expand(path, directory)

    cond do
      not inside?(artifact, directory) ->
        {:error,
         Error.exception(
           reason: :backend_failure,
           backend: Kinda.Sandbox.Backend.LocalNative,
           operation: :native_build,
           message: "native artifact is outside the sandbox directory",
           details: artifact
         )}

      not File.regular?(artifact) ->
        {:error,
         Error.exception(
           reason: :backend_failure,
           backend: Kinda.Sandbox.Backend.LocalNative,
           operation: :native_build,
           message: "native artifact is not a regular file",
           details: artifact
         )}

      true ->
        {:ok, artifact}
    end
  end

  defp inside?(path, directory) do
    relative = Path.relative_to(path, directory)
    Path.type(relative) == :relative and relative != ".." and hd(Path.split(relative)) != ".."
  end

  defp clean_after_failure(%Context{directory: directory}, error, builder_mfa) do
    with {:ok, _paths} <- File.rm_rf(directory),
         :ok <- File.mkdir_p(directory) do
      {:error, error}
    else
      cleanup_error ->
        {:error,
         Error.exception(
           reason: :backend_failure,
           backend: Kinda.Sandbox.Backend.LocalNative,
           operation: :native_build,
           message: "could not reset sandbox after a failed native build",
           details: %{builder: builder_mfa, cleanup: cleanup_error, build: error}
         )}
    end
  end
end
