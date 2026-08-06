defmodule Kinda.Wrapper.CallbackBridge do
  @moduledoc """
  Metadata for wrapper entries that require a callback-bridge layer.

  Pending and runtime-backed entries share this contract, so callback-backed
  declarations stay in the same resolved declaration surface as ordinary
  generated NIFs while retaining their ownership and scheduler requirements.
  """

  @type function_name :: atom()
  @type reason :: :callback_bridge_required | nil
  @type unblock_path :: :callback_bridge_runtime | nil
  @type scheduler :: :normal | :dirty_cpu | :dirty_io | :foreign_thread | :unspecified
  @type runtime :: :pending | :dispatcher
  @type owner :: :beam_process | :native_owner | :unspecified
  @type destructor :: :reply_token_resource | :consumer_callback | :native_owner | :unspecified
  @type lifetime :: :invocation | :registration | :native_owner | :unspecified
  @type facet ::
          :beam_callback
          | :lifetime_contract
          | :scheduler_contract
          | :rich_input_decoder

  @enforce_keys [:function, :reason]
  defstruct function: nil,
            reason: :callback_bridge_required,
            unblock_path: :callback_bridge_runtime,
            scheduler: :unspecified,
            facets: [],
            runtime: :pending,
            runtime_backed: false,
            owner: :unspecified,
            destructor: :unspecified,
            lifetime: :unspecified,
            timeout_ms: nil

  @type t :: %__MODULE__{
          function: function_name(),
          reason: reason(),
          unblock_path: unblock_path(),
          scheduler: scheduler(),
          facets: [facet()],
          runtime: runtime(),
          runtime_backed: boolean(),
          owner: owner(),
          destructor: destructor(),
          lifetime: lifetime(),
          timeout_ms: non_neg_integer() | nil
        }

  @spec required(function_name(), keyword()) :: t()
  def required(function, opts \\ []) do
    %__MODULE__{
      function: function,
      reason: :callback_bridge_required,
      unblock_path: Keyword.get(opts, :unblock_path, :callback_bridge_runtime),
      scheduler: Keyword.get(opts, :scheduler, :unspecified),
      facets: Keyword.get(opts, :facets, []),
      runtime: :pending,
      runtime_backed: false,
      owner: Keyword.get(opts, :owner, :unspecified),
      destructor: Keyword.get(opts, :destructor, :unspecified),
      lifetime: Keyword.get(opts, :lifetime, :unspecified),
      timeout_ms: Keyword.get(opts, :timeout_ms)
    }
  end

  @doc """
  Marks a callback declaration as resolved by Kinda's dispatcher runtime.

  Runtime-backed entries are not generation blockers. Consumers still own the
  ABI trampoline and type projection named by their declaration variant.
  """
  @spec runtime_backed(function_name(), keyword()) :: t()
  def runtime_backed(function, opts \\ []) do
    %__MODULE__{
      function: function,
      reason: nil,
      unblock_path: nil,
      scheduler: Keyword.get(opts, :scheduler, :foreign_thread),
      facets: Keyword.get(opts, :facets, []),
      runtime: :dispatcher,
      runtime_backed: true,
      owner: Keyword.fetch!(opts, :owner),
      destructor: Keyword.fetch!(opts, :destructor),
      lifetime: Keyword.fetch!(opts, :lifetime),
      timeout_ms: Keyword.get(opts, :timeout_ms, 30_000)
    }
  end
end
