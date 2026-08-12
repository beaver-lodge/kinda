defmodule Kinda.Resource.Declaration do
  @moduledoc """
  Declares the stable lifecycle contract of a native resource.

  Declarations are data: generated bindings and test tooling can inspect the
  same identity, ownership and upgrade promises without coupling production
  code to a test observer.
  """

  @enforce_keys [:identity]
  defstruct [:identity, :owner, abi_version: 1, upgrade: :unsupported]

  @type upgrade :: :unsupported | :takeover
  @type t :: %__MODULE__{
          identity: atom() | binary(),
          owner: atom() | binary() | nil,
          abi_version: pos_integer(),
          upgrade: upgrade()
        }

  @spec new(atom() | binary(), keyword()) :: t()
  def new(identity, options \\ []) when is_atom(identity) or is_binary(identity) do
    declaration = %__MODULE__{
      identity: identity,
      owner: Keyword.get(options, :owner),
      abi_version: Keyword.get(options, :abi_version, 1),
      upgrade: Keyword.get(options, :upgrade, :unsupported)
    }

    validate!(declaration)
  end

  @spec supports_upgrade?(t()) :: boolean()
  def supports_upgrade?(%__MODULE__{upgrade: :takeover}), do: true
  def supports_upgrade?(%__MODULE__{}), do: false

  defp validate!(%__MODULE__{abi_version: version}) when not is_integer(version) or version < 1,
    do: raise(ArgumentError, "resource ABI version must be a positive integer")

  defp validate!(%__MODULE__{upgrade: upgrade}) when upgrade not in [:unsupported, :takeover],
    do: raise(ArgumentError, "unsupported resource upgrade mode: #{inspect(upgrade)}")

  defp validate!(declaration), do: declaration
end
