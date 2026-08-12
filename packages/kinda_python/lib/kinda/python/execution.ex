defmodule Kinda.Python.Execution do
  @moduledoc "A linked BEAM task whose isolated interpreter never leaves one dirty scheduler call."
  alias Kinda.Python.Native
  @enforce_keys [:task]
  defstruct [:task]
  @opaque t :: %__MODULE__{task: Task.t()}
  @spec start(iodata()) :: t()
  def start(code),
    do: %__MODULE__{task: Task.async(fn -> Native.isolated_eval(IO.iodata_to_binary(code)) end)}

  @spec await(t(), timeout()) :: term()
  def await(%__MODULE__{task: task}, timeout \\ 5_000), do: Task.await(task, timeout)
  @spec shutdown(t(), timeout() | :brutal_kill) :: term() | nil
  def shutdown(%__MODULE__{task: task}, timeout \\ 5_000), do: Task.shutdown(task, timeout)
end
