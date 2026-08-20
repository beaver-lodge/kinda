defmodule Kinda.Sandbox.Command do
  @moduledoc "Runs a structured executable and argv through a sandbox command capability."

  alias Kinda.Sandbox.Command.{Execution, Result, Spec}
  alias Kinda.Sandbox.{Error, ExecutionServer, Handle, HandleServer}

  @type result(value) :: {:ok, value} | {:error, Error.t()}

  @spec start(Handle.t(), Spec.t()) :: result(Execution.t())
  def start(%Handle{ref: ref}, %Spec{} = spec) do
    with :ok <- Spec.validate(spec) do
      HandleServer.command(ref, spec)
    end
  end

  def start(%Handle{}, spec), do: Spec.validate(spec)

  @spec run(Handle.t(), Spec.t(), timeout()) :: result(Result.t())
  def run(handle, spec, await_timeout \\ :infinity) do
    with {:ok, execution} <- start(handle, spec) do
      await(execution, await_timeout)
    end
  end

  @spec await(Execution.t(), timeout()) :: result(Result.t())
  def await(%Execution{ref: ref}, timeout \\ :infinity) do
    ExecutionServer.await(ref, timeout)
  end

  @spec cancel(Execution.t()) :: :ok | {:error, Error.t()}
  def cancel(%Execution{ref: ref}), do: ExecutionServer.cancel(ref)
end
