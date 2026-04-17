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
             scheduler: :normal,
             facets: [:beam_callback, :rich_input_decoder]
           }
  end
end
