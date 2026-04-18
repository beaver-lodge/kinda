defmodule Kinda.Wrapper.GenerateTest do
  use ExUnit.Case, async: true

  alias Kinda.Wrapper.Function
  alias Kinda.Wrapper.Generate
  alias Kinda.Wrapper.Manifest
  alias Kinda.Wrapper.Policy
  alias Kinda.CodeGen.NIFDecl

  defmodule FakePolicy do
    @behaviour Policy

    def generation_blocker_entries, do: %{}
    def generation_blocked?(_name), do: false
    def generation_blocker_reason(_name), do: nil
    def unsupported_entries, do: generation_blocker_entries()
    def unsupported?(name), do: generation_blocked?(name)
    def unsupported_reason(name), do: generation_blocker_reason(name)

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

    def variants(:bar),
      do: [{:normal, :bar, :bar}, {:with_diagnostics, :barWithDiagnostics, :bar}]

    def variants(:baz), do: []

    def public_name({_kind, public_name, _base_name}), do: public_name

    def elixir_params({:with_diagnostics, _public_name, _base_name}, params),
      do: [:context | params]

    def elixir_params({_kind, _public_name, _base_name}, params), do: params
    def dirty({:dirty_cpu, _public_name, _base_name}), do: :dirty_cpu
    def dirty({:dirty_io, _public_name, _base_name}), do: :dirty_io
    def dirty({_kind, _public_name, _base_name}), do: false
    def doc({_kind, _public_name, _base_name}, %Function{doc: doc}), do: doc

    def zig_entry({:normal, _public_name, base_name}), do: ~s{nif("#{base_name}"),}

    def zig_entry({:with_diagnostics, _public_name, base_name}),
      do: ~s{diagnostic.WithDiagnosticsNIF("#{base_name}"),}
  end

  defmodule DirtyPolicy do
    @behaviour Policy

    def generation_blocker_entries, do: %{}
    def generation_blocked?(_name), do: false
    def generation_blocker_reason(_name), do: nil
    def unsupported_entries, do: generation_blocker_entries()
    def unsupported?(name), do: generation_blocked?(name)
    def unsupported_reason(name), do: generation_blocker_reason(name)
    def callback_bridge_entries, do: %{}
    def callback_bridge?(_name), do: false
    def callback_bridge(_name), do: nil
    def variants(:invoke), do: [{:dirty_cpu, :invoke_dirty_cpu, :invoke}]
    def public_name({_kind, public_name, _base_name}), do: public_name
    def elixir_params({_kind, _public_name, _base_name}, params), do: params
    def dirty({:dirty_cpu, _public_name, _base_name}), do: :dirty_cpu
    def dirty({_kind, _public_name, _base_name}), do: false
    def doc({_kind, _public_name, _base_name}, %Function{doc: doc}), do: doc

    def zig_entry({:dirty_cpu, public_name, base_name}),
      do: ~s{nifDirtyCPU("#{base_name}", "#{public_name}"),}
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

  test "builds elixir nif decls with docs" do
    manifest = %Manifest{
      functions: [
        %Function{name: "bar", params: ["ctx"], arity: 1, doc: "Creates bar."},
        %Function{name: "foo", params: [], arity: 0, doc: "Creates foo."}
      ]
    }

    assert Generate.elixir_nif_decls(manifest, FakePolicy) == [
             %NIFDecl{wrapper_name: :bar, params: [:ctx], doc: "Creates bar.", dirty: false},
             %NIFDecl{
               wrapper_name: :barWithDiagnostics,
               params: [:context, :ctx],
               doc: "Creates bar.",
               dirty: false
             },
             %NIFDecl{wrapper_name: :foo, params: [], doc: "Creates foo.", dirty: false}
           ]
  end

  test "preserves dirty metadata in generated nif decls" do
    manifest = %Manifest{
      functions: [
        %Function{
          name: "invoke",
          params: ["engine", "args"],
          arity: 2,
          doc: "Invokes a function."
        }
      ]
    }

    assert Generate.elixir_nif_decls(manifest, DirtyPolicy) == [
             %NIFDecl{
               wrapper_name: :invoke_dirty_cpu,
               params: [:engine, :args],
               doc: "Invokes a function.",
               dirty: :dirty_cpu
             }
           ]
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
                 unblock_path: :callback_bridge_runtime,
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

  test "builds a versioned callback-bridge manifest contract" do
    manifest = %Manifest{
      functions: [
        %Function{name: "baz", params: ["value"], arity: 1},
        %Function{name: "foo", params: [], arity: 0}
      ]
    }

    assert Generate.callback_bridge_manifest(manifest, FakePolicy) == %{
             "version" => 1,
             "entries" => [
               %{
                 "function" => %{
                   "name" => "baz",
                   "arity" => 1,
                   "params" => ["value"],
                   "doc" => nil
                 },
                 "callback_bridge" => %{
                   "function" => "baz",
                   "reason" => "callback_bridge_required",
                   "unblock_path" => "callback_bridge_runtime",
                   "scheduler" => "dirty_cpu",
                   "facets" => ["beam_callback", "scheduler_contract"]
                 }
               }
             ]
           }
  end

  test "preserves extracted docs in callback-bridge manifests" do
    manifest = %Manifest{
      functions: [
        %Function{name: "baz", params: ["value"], arity: 1, doc: "Converts a callback."}
      ]
    }

    assert %{
             "entries" => [
               %{
                 "function" => %{
                   "name" => "baz",
                   "doc" => "Converts a callback."
                 }
               }
             ]
           } = Generate.callback_bridge_manifest(manifest, FakePolicy)
  end
end
