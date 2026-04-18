defmodule Kinda.Wrapper.Function do
  @moduledoc """
  Normalized function declaration extracted from a wrapper surface.
  """

  alias Kinda.CodeGen.TypeSpecRef
  alias Kinda.Wrapper.CType

  @enforce_keys [:name, :params, :arity]
  defstruct [:name, :params, :arity, :doc, param_ctypes: [], return_ctype: nil]

  @type t :: %__MODULE__{
          name: String.t(),
          params: [String.t()],
          arity: non_neg_integer(),
          doc: String.t() | nil,
          param_ctypes: [CType.t() | nil],
          return_ctype: CType.t() | nil
        }

  @spec typespec_params(t(), [atom()], (CType.t() | nil -> TypeSpecRef.t())) :: [TypeSpecRef.t()]
  def typespec_params(%__MODULE__{} = function, emitted_params, mapper)
      when is_list(emitted_params) and is_function(mapper, 1) do
    lookup =
      function.params
      |> Enum.map(&String.to_atom/1)
      |> Enum.zip(function.param_ctypes)
      |> Map.new()

    Enum.map(emitted_params, fn param ->
      lookup
      |> Map.get(param)
      |> mapper.()
    end)
  end
end
