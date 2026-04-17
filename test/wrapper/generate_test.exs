defmodule Kinda.Wrapper.GenerateTest do
  use ExUnit.Case, async: true

  alias Kinda.Wrapper.Function
  alias Kinda.Wrapper.Generate
  alias Kinda.Wrapper.Manifest

  defmodule FakePolicy do
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
end
