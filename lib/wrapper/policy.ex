defmodule Kinda.Wrapper.Policy do
  @moduledoc """
  Consumer-facing policy contract for wrapper generation.

  `Kinda.Wrapper.Extract` and `Kinda.Wrapper.Generate` stay generic.
  Downstream projects provide the policy that decides:

  - which extracted functions are unsupported
  - which extracted functions require a future callback-bridge layer
  - which public variants are emitted
  - how Elixir arities and Zig NIF entries are derived
  """

  alias Kinda.Wrapper.CallbackBridge

  @type function_name :: atom()
  @type params :: [atom()]
  @type unsupported_reason :: atom()
  @type variant :: term()

  @callback unsupported_entries() :: %{optional(function_name()) => unsupported_reason()}
  @callback unsupported?(function_name()) :: boolean()
  @callback unsupported_reason(function_name()) :: unsupported_reason() | nil
  @callback callback_bridge_entries() :: %{optional(function_name()) => CallbackBridge.t()}
  @callback callback_bridge?(function_name()) :: boolean()
  @callback callback_bridge(function_name()) :: CallbackBridge.t() | nil
  @callback variants(function_name()) :: [variant()]
  @callback public_name(variant()) :: atom()
  @callback elixir_params(variant(), params()) :: params()
  @callback zig_entry(variant()) :: String.t()
end
