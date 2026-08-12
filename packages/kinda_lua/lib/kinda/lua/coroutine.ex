defmodule Kinda.Lua.Coroutine do
  @moduledoc "A resumable Lua coroutine owned by its parent VM."
  alias Kinda.Lua.{Native, VM}
  @enforce_keys [:resource]
  defstruct [:resource]
  @opaque t :: %__MODULE__{resource: reference()}

  @spec new(VM.t(), iodata()) :: t()
  def new(%VM{resource: vm}, code) do
    %__MODULE__{resource: Native.create_coroutine(vm, IO.iodata_to_binary(code))}
  end

  @spec resume(t()) :: {:yielded | :done, [term()]}
  def resume(%__MODULE__{resource: resource}), do: Native.resume_coroutine(resource)

  @spec close(t()) :: :ok
  def close(%__MODULE__{resource: resource}), do: Native.close_coroutine(resource)
end
