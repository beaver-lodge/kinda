defmodule Kinda.Wrapper.ExtractTest do
  use ExUnit.Case, async: true

  alias Kinda.Wrapper.Extract
  alias Kinda.Wrapper.CType
  alias Kinda.Wrapper.Function
  alias Kinda.Wrapper.Manifest

  test "extracts a normalized manifest from clang ast" do
    ast = %{
      "kind" => "TranslationUnitDecl",
      "inner" => [
        %{
          "kind" => "FunctionDecl",
          "name" => "mlirFoo",
          "type" => %{"qualType" => "MlirContext (MlirContext, intptr_t)"},
          "inner" => [
            %{"kind" => "ParmVarDecl", "name" => "ctx", "type" => %{"qualType" => "MlirContext"}},
            %{"kind" => "ParmVarDecl", "type" => %{"qualType" => "intptr_t"}},
            %{
              "kind" => "FullComment",
              "inner" => [
                %{
                  "kind" => "ParagraphComment",
                  "inner" => [
                    %{"kind" => "TextComment", "text" => " Creates foo."}
                  ]
                },
                %{
                  "kind" => "ParamCommandComment",
                  "param" => "ctx",
                  "inner" => [
                    %{
                      "kind" => "ParagraphComment",
                      "inner" => [
                        %{"kind" => "TextComment", "text" => " Context value."}
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        },
        %{
          "kind" => "NamespaceDecl",
          "inner" => [
            %{
              "kind" => "FunctionDecl",
              "name" => "mlirBar",
              "inner" => []
            }
          ]
        }
      ]
    }

    assert Extract.from_clang_ast(ast) == %Manifest{
             functions: [
               %Function{
                 name: "mlirBar",
                 params: [],
                 param_ctypes: [],
                 arity: 0,
                 doc: nil,
                 return_ctype: nil
               },
               %Function{
                 name: "mlirFoo",
                 params: ["ctx", "param_1"],
                 param_ctypes: [
                   %CType{spelling: "MlirContext", kind: :unknown},
                   %CType{spelling: "intptr_t", kind: :integer}
                 ],
                 arity: 2,
                 doc: "Creates foo.\n\nParameters:\n- `ctx`: Context value.",
                 return_ctype: %CType{spelling: "MlirContext", kind: :unknown}
               }
             ]
           }
  end

  test "repairs malformed clang comment code spans without damaging valid ones" do
    ast = %{
      "kind" => "TranslationUnitDecl",
      "inner" => [
        %{
          "kind" => "FunctionDecl",
          "name" => "mlirBrokenDoc",
          "inner" => [
            %{
              "kind" => "FullComment",
              "inner" => [
                %{
                  "kind" => "ParagraphComment",
                  "inner" => [
                    %{
                      "kind" => "TextComment",
                      "text" =>
                        " Uses `llvm.emit_c_interface` and forwards `userData to `callback`."
                    }
                  ]
                },
                %{
                  "kind" => "ParagraphComment",
                  "inner" => [
                    %{
                      "kind" => "TextComment",
                      "text" =>
                        " Creates a `sparse_tensor.encoding` attribute and stores it in a `std::string`."
                    },
                    %{
                      "kind" => "TextComment",
                      "text" =>
                        " Sets multiple current debug types, similarly to `-debug-only=type1,type2\" in the command-line tools."
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }

    assert %Manifest{
             functions: [
               %Function{
                 name: "mlirBrokenDoc",
                 param_ctypes: [],
                 doc:
                   "Uses `llvm.emit_c_interface` and forwards `userData` to `callback`.\n\nCreates a `sparse_tensor.encoding` attribute and stores it in a `std::string`. Sets multiple current debug types, similarly to `-debug-only=type1,type2` in the command-line tools."
               }
             ]
           } = Extract.from_clang_ast(ast)
  end

  test "formats inline bullet sections as markdown parameter lists" do
    ast = %{
      "kind" => "TranslationUnitDecl",
      "inner" => [
        %{
          "kind" => "FunctionDecl",
          "name" => "mlirStreamDoc",
          "inner" => [
            %{
              "kind" => "FullComment",
              "inner" => [
                %{
                  "kind" => "ParagraphComment",
                  "inner" => [
                    %{
                      "kind" => "TextComment",
                      "text" =>
                        " Create a raw_fd_ostream for the given path. This wrapper is needed because"
                    },
                    %{
                      "kind" => "TextComment",
                      "text" =>
                        " std::ostream does not provide the file sharing semantics required on"
                    },
                    %{"kind" => "TextComment", "text" => " Windows."},
                    %{"kind" => "TextComment", "text" => " - `path`: output file path."},
                    %{
                      "kind" => "TextComment",
                      "text" => " - `binary`: controls text vs binary mode."
                    },
                    %{
                      "kind" => "TextComment",
                      "text" =>
                        " - `userData`: forwarded to `errorCallback` so it can copy the error message"
                    },
                    %{
                      "kind" => "TextComment",
                      "text" => "   into caller-owned storage (e.g., a `std::string`)."
                    },
                    %{
                      "kind" => "TextComment",
                      "text" =>
                        " On failure, returns a null stream and invokes the optional error callback with the error message."
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }

    assert %Manifest{
             functions: [
               %Function{
                 name: "mlirStreamDoc",
                 param_ctypes: [],
                 doc:
                   "Create a raw_fd_ostream for the given path. This wrapper is needed because std::ostream does not provide the file sharing semantics required on Windows.\n\nParameters:\n- `path`: output file path.\n- `binary`: controls text vs binary mode.\n- `userData`: forwarded to `errorCallback` so it can copy the error message into caller-owned storage (e.g., a `std::string`).\n\nOn failure, returns a null stream and invokes the optional error callback with the error message."
               }
             ]
           } = Extract.from_clang_ast(ast)
  end
end
