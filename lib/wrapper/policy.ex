defmodule Kinda.Wrapper.Policy do
  @moduledoc """
  Consumer-facing policy contract for wrapper generation.

  `Kinda.Wrapper.Extract` and `Kinda.Wrapper.Generate` stay generic.
  Downstream projects provide the policy that decides:

  - which extracted functions are generation-blocked
  - which extracted functions require a future callback-bridge layer
  - which public variants are emitted
  - how Elixir arities and Zig NIF entries are derived

  The older `unsupported_*` callbacks remain as compatibility aliases, but they
  are no longer the preferred public vocabulary for new policy code.
  """

  alias Kinda.Wrapper.CallbackBridge
  alias Kinda.Wrapper.Function

  @type function_name :: atom()
  @type params :: [atom()]
  @type generation_blocker_reason :: atom()
  @type unsupported_reason :: atom()
  @type variant :: term()

  @callback generation_blocker_entries() :: %{
              optional(function_name()) => generation_blocker_reason()
            }
  @callback generation_blocked?(function_name()) :: boolean()
  @callback generation_blocker_reason(function_name()) :: generation_blocker_reason() | nil

  @callback unsupported_entries() :: %{optional(function_name()) => unsupported_reason()}
  @callback unsupported?(function_name()) :: boolean()
  @callback unsupported_reason(function_name()) :: unsupported_reason() | nil
  @callback callback_bridge_entries() :: %{optional(function_name()) => CallbackBridge.t()}
  @callback callback_bridge?(function_name()) :: boolean()
  @callback callback_bridge(function_name()) :: CallbackBridge.t() | nil
  @callback variants(function_name()) :: [variant()]
  @callback public_name(variant()) :: atom()
  @callback elixir_params(variant(), params()) :: params()
  @callback dirty(variant()) :: Kinda.CodeGen.NIFDecl.dirty()
  @callback doc(variant(), Function.t()) :: String.t() | nil
  @callback zig_entry(variant()) :: String.t()

  @optional_callbacks unsupported_entries: 0, unsupported?: 1, unsupported_reason: 1
end
