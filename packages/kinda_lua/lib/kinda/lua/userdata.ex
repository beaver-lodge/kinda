defmodule Kinda.Lua.Userdata do
  @moduledoc "Full Lua userdata rooted in, and owned by, one VM."
  alias Kinda.Lua.{Native, VM}
  @enforce_keys [:resource]
  defstruct [:resource]
  @opaque t :: %__MODULE__{resource: reference()}

  @spec new(VM.t(), integer()) :: t()
  def new(%VM{resource: vm}, value), do: %__MODULE__{resource: Native.create_userdata(vm, value)}

  @spec value(t()) :: integer()
  def value(%__MODULE__{resource: resource}), do: Native.userdata_value(resource)

  @spec close(t()) :: :ok
  def close(%__MODULE__{resource: resource}), do: Native.close_userdata(resource)
end
