defmodule Kinda.Wrapper.CallbackBridge do
  @moduledoc """
  Metadata for wrapper entries that cannot yet be emitted as ordinary generated
  NIFs because they require a future callback-bridge layer.
  """

  @type function_name :: atom()
  @type reason :: :callback_bridge_required
  @type scheduler :: :normal | :dirty_cpu | :dirty_io | :unspecified
  @type facet ::
          :beam_callback
          | :lifetime_contract
          | :scheduler_contract
          | :rich_input_decoder

  @enforce_keys [:function, :reason]
  defstruct function: nil,
            reason: :callback_bridge_required,
            scheduler: :unspecified,
            facets: []

  @type t :: %__MODULE__{
          function: function_name(),
          reason: reason(),
          scheduler: scheduler(),
          facets: [facet()]
        }

  @spec required(function_name(), keyword()) :: t()
  def required(function, opts \\ []) do
    %__MODULE__{
      function: function,
      reason: :callback_bridge_required,
      scheduler: Keyword.get(opts, :scheduler, :unspecified),
      facets: Keyword.get(opts, :facets, [])
    }
  end
end
