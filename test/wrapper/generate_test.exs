defmodule Kinda.Wrapper.GenerateTest do
  use ExUnit.Case, async: true

  alias Kinda.Wrapper.Function
  alias Kinda.Wrapper.Generate
  alias Kinda.Wrapper.Manifest
  alias Kinda.Wrapper.Policy

  defmodule FakePolicy do
    @behaviour Policy

    def unsupported_entries, do: %{}
    def unsupported?(_name), do: false
    def unsupported_reason(_name), do: nil
    def callback_bridge_entries do
      %{
        baz:
          Kinda.Wrapper.CallbackBridge.required(:baz,
            scheduler: :dirty_cpu,
            facets: [:beam_callback, :scheduler_contract]
          ),
        qux:
          Kinda.Wrapper.CallbackBridge.required(:qux,
            facets: [:beam_callback]
          )
      }
    end

    def callback_bridge?(name), do: Map.has_key?(callback_bridge_entries(), name)
    def callback_bridge(name), do: Map.get(callback_bridge_entries(), name)
    def variants(:foo), do: [{:normal, :foo, :foo}]
    def variants(:bar), do: [{:normal, :bar, :bar}, {:with_diagnostics, :barWithDiagnostics, :bar}]
    def variants(:baz), do: []

    def public_name({_kind, public_name, _base_name}), do: public_name

    def elixir_params({:with_diagnostics, _public_name, _base_name}, params), do: [:context | params]
    def elixir_params({_kind, _public_name, _base_name}, params), do: params

    def zig_entry({:normal, _public_name, base_name}), do: ~s{nif("#{base_name}"),}
    def zig_entry({:with_diagnostics, _public_name, base_name}), do: ~s{diagnostic.WithDiagnosticsNIF("#{base_name}"),}
  end

  test "renders generic elixir and zig outputs from manifest + policy" do
    manifest = %Manifest{
      functions: [
        %Function{name: "bar", params: ["ctx"], arity: 1},
        %Function{name: "baz", params: ["ignored"], arity: 1},
        %Function{name: "foo", params: [], arity: 0}
      ]
    }

    assert Generate.elixir_functions(manifest, FakePolicy) == [
             {:bar, [:ctx]},
             {:barWithDiagnostics, [:context, :ctx]},
             {:foo, []}
           ]

    zig = Generate.render_zig_nif_entries(manifest, FakePolicy)
    assert zig =~ ~s{nif("bar"),}
    assert zig =~ ~s{diagnostic.WithDiagnosticsNIF("bar"),}
    assert zig =~ ~s{nif("foo"),}
    refute zig =~ ~s{baz}
  end

  test "renders callback-bridge backlog from extracted functions only" do
    manifest = %Manifest{
      functions: [
        %Function{name: "baz", params: ["value"], arity: 1},
        %Function{name: "foo", params: [], arity: 0}
      ]
    }

    assert Generate.callback_bridge_backlog(manifest, FakePolicy) == [
             %{
               function: %Function{name: "baz", params: ["value"], arity: 1},
               callback_bridge: %Kinda.Wrapper.CallbackBridge{
                 function: :baz,
                 reason: :callback_bridge_required,
                 scheduler: :dirty_cpu,
                 facets: [:beam_callback, :scheduler_contract]
               }
             }
           ]

    report = Generate.render_callback_bridge_report(manifest, FakePolicy)
    assert report =~ ":callback_bridge_required"
    assert report =~ "dirty_cpu"
    assert report =~ "\"baz\""
    refute report =~ ":qux"
  end
end
