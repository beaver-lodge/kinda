defmodule Kinda.QuickJS.Bytecode do
  @moduledoc "QuickJS 2026-06-04-bound bytecode."
  alias Kinda.QuickJS.Native
  @enforce_keys [:resource]
  defstruct [:resource]
  @opaque t :: %__MODULE__{resource: reference()}

  @spec close(t()) :: :ok
  def close(%__MODULE__{resource: bytecode}), do: Native.close_bytecode(bytecode)
end
