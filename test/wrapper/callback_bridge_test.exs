defmodule Kinda.Wrapper.CallbackBridgeTest do
  use ExUnit.Case, async: true

  alias Kinda.Wrapper.CallbackBridge

  test "builds required callback-bridge metadata" do
    assert CallbackBridge.required(:mlirTypeConverterAddConversion,
             scheduler: :normal,
             facets: [:beam_callback, :rich_input_decoder]
           ) == %CallbackBridge{
             function: :mlirTypeConverterAddConversion,
             reason: :callback_bridge_required,
             unblock_path: :callback_bridge_runtime,
             scheduler: :normal,
             facets: [:beam_callback, :rich_input_decoder]
           }
  end

  test "builds explicit runtime-backed ownership metadata" do
    assert %CallbackBridge{
             function: :mlirTypeConverterAddConversion,
             reason: nil,
             unblock_path: nil,
             scheduler: :foreign_thread,
             runtime: :dispatcher,
             runtime_backed: true,
             owner: :beam_process,
             destructor: :native_owner,
             lifetime: :native_owner,
             timeout_ms: 250
           } =
             CallbackBridge.runtime_backed(:mlirTypeConverterAddConversion,
               owner: :beam_process,
               destructor: :native_owner,
               lifetime: :native_owner,
               timeout_ms: 250
             )
  end
end
