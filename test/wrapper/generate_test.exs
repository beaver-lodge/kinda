defmodule Kinda.Wrapper.GenerateTest do
  use ExUnit.Case, async: true

  alias Kinda.Wrapper.Function
  alias Kinda.Wrapper.CField
  alias Kinda.Wrapper.CRecord
  alias Kinda.Wrapper.Generate
  alias Kinda.Wrapper.Manifest
  alias Kinda.Wrapper.Policy
  alias Kinda.CodeGen.{NIFDecl, TypeSpecRef}
  alias Kinda.Wrapper.CType

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
             %NIFDecl{
               wrapper_name: :bar,
               params: [:ctx],
               doc: "Creates bar.",
               param_ctypes: [],
               return_ctype: nil,
               param_typespecs: [TypeSpecRef.term()],
               return_typespec: TypeSpecRef.term(),
               dirty: false
             },
             %NIFDecl{
               wrapper_name: :barWithDiagnostics,
               params: [:context, :ctx],
               doc: "Creates bar.",
               param_ctypes: [],
               return_ctype: nil,
               param_typespecs: [TypeSpecRef.term(), TypeSpecRef.term()],
               return_typespec: TypeSpecRef.term(),
               dirty: false
             },
             %NIFDecl{
               wrapper_name: :foo,
               params: [],
               doc: "Creates foo.",
               param_ctypes: [],
               return_ctype: nil,
               param_typespecs: [],
               return_typespec: TypeSpecRef.term(),
               dirty: false
             }
           ]
  end

  test "preserves typed c signature metadata in generated nif decls" do
    manifest = %Manifest{
      functions: [
        %Function{
          name: "foo",
          params: ["ctx", "count"],
          param_ctypes: [
            %CType{spelling: "MlirContext", kind: :unknown},
            %CType{spelling: "intptr_t", kind: :integer}
          ],
          arity: 2,
          return_ctype: %CType{spelling: "bool", kind: :bool}
        }
      ]
    }

    assert [
             %NIFDecl{
               wrapper_name: :foo,
               param_ctypes: [
                 %CType{spelling: "MlirContext", kind: :unknown},
                 %CType{spelling: "intptr_t", kind: :integer}
               ],
               return_ctype: %CType{spelling: "bool", kind: :bool},
               param_typespecs: [:term, :integer],
               return_typespec: :boolean
             }
           ] = Generate.elixir_nif_decls(manifest, FakePolicy)
  end

  test "builds a versioned typed signature manifest contract" do
    manifest = %Manifest{
      records: [
        %CRecord{
          name: "MlirContext",
          kind: :struct,
          fields: [
            %CField{name: "ptr", ctype: %CType{spelling: "void*", kind: :pointer}}
          ]
        }
      ],
      functions: [
        %Function{
          name: "baz",
          params: ["value"],
          arity: 1,
          doc: "Needs a callback bridge."
        },
        %Function{
          name: "foo",
          params: ["ctx", "count"],
          param_ctypes: [
            %CType{spelling: "MlirContext", kind: :unknown},
            %CType{spelling: "intptr_t", kind: :integer}
          ],
          arity: 2,
          doc: "Creates foo.",
          return_ctype: %CType{spelling: "bool", kind: :bool}
        }
      ]
    }

    assert Generate.signature_manifest(manifest, FakePolicy) == %{
             "version" => 1,
             "records" => [
               %{
                 "name" => "MlirContext",
                 "kind" => "struct",
                 "public_typespec" => %{
                   "kind" => "map",
                   "fields" => [
                     %{
                       "name" => "ptr",
                       "type" => %{"kind" => "builtin", "name" => "term"}
                     }
                   ]
                 },
                 "fields" => [
                   %{
                     "name" => "ptr",
                     "ctype" => %{"spelling" => "void*", "kind" => "pointer"},
                     "typespec" => %{"kind" => "builtin", "name" => "term"}
                   }
                 ]
               }
             ],
             "entries" => [
               %{
                 "function" => %{
                   "name" => "baz",
                   "arity" => 1,
                   "params" => ["value"],
                   "doc" => "Needs a callback bridge.",
                   "param_ctypes" => [],
                   "return_ctype" => nil
                 },
                 "generation_blocker_reason" => "callback_bridge_required",
                 "variants" => []
               },
               %{
                 "function" => %{
                   "name" => "foo",
                   "arity" => 2,
                   "params" => ["ctx", "count"],
                   "doc" => "Creates foo.",
                   "param_ctypes" => [
                     %{"spelling" => "MlirContext", "kind" => "unknown"},
                     %{"spelling" => "intptr_t", "kind" => "integer"}
                   ],
                   "return_ctype" => %{"spelling" => "bool", "kind" => "bool"}
                 },
                 "generation_blocker_reason" => nil,
                 "variants" => [
                   %{
                     "wrapper_name" => "foo",
                     "params" => ["ctx", "count"],
                     "doc" => "Creates foo.",
                     "dirty" => false,
                     "param_typespecs" => [
                       %{"kind" => "builtin", "name" => "term"},
                       %{"kind" => "builtin", "name" => "integer"}
                     ],
                     "return_typespec" => %{"kind" => "builtin", "name" => "boolean"}
                   }
                 ]
               }
             ]
           }
  end

  test "builds a unified declaration manifest contract" do
    manifest = %Manifest{
      records: [
        %CRecord{
          name: "MlirContext",
          kind: :struct,
          fields: [
            %CField{name: "ptr", ctype: %CType{spelling: "void*", kind: :pointer}}
          ]
        }
      ],
      functions: [
        %Function{
          name: "foo",
          params: ["ctx"],
          param_ctypes: [%CType{spelling: "MlirContext", kind: :unknown}],
          arity: 1,
          doc: "Creates foo.",
          return_ctype: %CType{spelling: "bool", kind: :bool}
        }
      ]
    }

    assert Generate.declaration_manifest(manifest, FakePolicy) == %{
             "version" => 1,
             "signature_manifest_version" => 1,
             "signature_manifest" => %{
               "version" => 1,
               "records" => [
                 %{
                   "name" => "MlirContext",
                   "kind" => "struct",
                   "public_typespec" => %{
                     "kind" => "map",
                     "fields" => [
                       %{
                         "name" => "ptr",
                         "type" => %{"kind" => "builtin", "name" => "term"}
                       }
                     ]
                   },
                   "fields" => [
                     %{
                       "name" => "ptr",
                       "ctype" => %{"spelling" => "void*", "kind" => "pointer"},
                       "typespec" => %{"kind" => "builtin", "name" => "term"}
                     }
                   ]
                 }
               ],
               "entries" => [
                 %{
                   "function" => %{
                     "name" => "foo",
                     "arity" => 1,
                     "params" => ["ctx"],
                     "doc" => "Creates foo.",
                     "param_ctypes" => [%{"spelling" => "MlirContext", "kind" => "unknown"}],
                     "return_ctype" => %{"spelling" => "bool", "kind" => "bool"}
                   },
                   "generation_blocker_reason" => nil,
                   "variants" => [
                     %{
                       "wrapper_name" => "foo",
                       "params" => ["ctx"],
                       "doc" => "Creates foo.",
                       "dirty" => false,
                       "param_typespecs" => [%{"kind" => "builtin", "name" => "term"}],
                       "return_typespec" => %{"kind" => "builtin", "name" => "boolean"}
                     }
                   ]
                 }
               ]
             },
             "nif_decls" => [
               %{
                 "wrapper_name" => "foo",
                 "nif_name" => nil,
                 "params" => ["ctx"],
                 "doc" => "Creates foo.",
                 "param_ctypes" => [%{"spelling" => "MlirContext", "kind" => "unknown"}],
                 "return_ctype" => %{"spelling" => "bool", "kind" => "bool"},
                 "param_typespecs" => [%{"kind" => "builtin", "name" => "term"}],
                 "return_typespec" => %{"kind" => "builtin", "name" => "boolean"},
                 "dirty" => false
               }
             ],
             "type_decls" => [
               %{
                 "name" => "mlir_context_record",
                 "source_record_name" => "MlirContext",
                 "doc" => "Typed projection for extracted C record MlirContext.",
                 "typespec" => %{
                   "kind" => "map",
                   "fields" => [
                     %{
                       "name" => "ptr",
                       "type" => %{"kind" => "builtin", "name" => "term"}
                     }
                   ]
                 }
               }
             ]
           }
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
               param_ctypes: [],
               return_ctype: nil,
               param_typespecs: [TypeSpecRef.term(), TypeSpecRef.term()],
               return_typespec: TypeSpecRef.term(),
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
