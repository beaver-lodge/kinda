defmodule Kinda.CodeGenTest do
  use ExUnit.Case, async: true

  alias Kinda.CodeGen
  alias Kinda.CodeGen.{NIFDecl, TypeDecl, TypeSpecRef}

  defmodule GeneratedDecls do
    @behaviour Kinda.CodeGen

    @impl true
    def kinds, do: []

    @impl true
    def nifs do
      [
        %NIFDecl{
          wrapper_name: :invoke_dirty_cpu,
          params: [:engine],
          doc: "Invokes the engine.",
          dirty: :dirty_cpu
        }
      ]
    end

    @impl true
    def signature_manifest do
      %{
        "version" => 1,
        "records" => [
          %{
            "name" => "FooHandle",
            "kind" => "struct",
            "public_typespec" => %{"kind" => "map", "fields" => []},
            "fields" => []
          }
        ],
        "entries" => []
      }
    end
  end

  defmodule Forward do
    def check!(value), do: value
  end

  defmodule GeneratedModule do
    use Kinda.CodeGen,
      with: Kinda.CodeGenTest.GeneratedDecls,
      root: Kinda.CodeGenTest.GeneratedModule,
      forward: Kinda.CodeGenTest.Forward
  end

  test "emits docs on generated public wrappers" do
    {ast, _exports} =
      CodeGen.nif_ast(
        [],
        [
          %NIFDecl{
            wrapper_name: :mlirFoo,
            params: [:ctx],
            doc: "Creates foo.\n\nParameters:\n- `ctx`: Context value.",
            param_typespecs: [TypeSpecRef.term()],
            return_typespec: TypeSpecRef.integer()
          }
        ],
        Module.concat(__MODULE__, GeneratedDocs),
        Forward
      )

    ast_string = ast |> then(&{:__block__, [], &1}) |> Macro.to_string()

    assert ast_string =~ ~s(@doc "Creates foo.)
    assert ast_string =~ "@spec mlirFoo(term()) :: integer()"
    assert ast_string =~ "defmodule Raw"
    assert ast_string =~ "def mlirFoo(ctx)"
    assert ast_string =~ "GeneratedDocs.Raw"
    assert ast_string =~ "Kinda.Forwarder.invoke_public_nif"
  end

  test "exposes generated nif declarations as module metadata" do
    assert [
             %NIFDecl{
               wrapper_name: :invoke_dirty_cpu,
               params: [:engine],
               doc: "Invokes the engine.",
               dirty: :dirty_cpu
             }
           ] = GeneratedModule.__kinda_nif_decls__()
  end

  test "exposes optional typed signature manifest metadata" do
    assert GeneratedModule.__kinda_signature_manifest__() == %{
             "version" => 1,
             "records" => [
               %{
                 "name" => "FooHandle",
                 "kind" => "struct",
                 "public_typespec" => %{"kind" => "map", "fields" => []},
                 "fields" => []
               }
             ],
             "entries" => []
           }
  end

  test "emits generated record type aliases from signature manifest" do
    type_decls =
      CodeGen.type_decls(%{
        "records" => [
          %{
            "name" => "FooHandle",
            "public_typespec" => %{
              "kind" => "map",
              "fields" => [
                %{"name" => "ptr", "type" => %{"kind" => "builtin", "name" => "term"}},
                %{
                  "name" => "location",
                  "type" => %{
                    "kind" => "remote",
                    "module" => "Elixir.Foo.Location",
                    "type" => "t"
                  }
                }
              ]
            }
          }
        ]
      })

    assert type_decls == [
             %TypeDecl{
               name: :foo_handle_record,
               source_record_name: "FooHandle",
               doc: "Typed projection for extracted C record FooHandle.",
               typespec:
                 TypeSpecRef.map([
                   {"ptr", TypeSpecRef.term()},
                   {"location", TypeSpecRef.remote(Foo.Location)}
                 ])
             }
           ]

    ast = CodeGen.type_decls_ast(type_decls)
    ast_string = ast |> then(&{:__block__, [], &1}) |> Macro.to_string()

    assert ast_string =~ "@typedoc \"Typed projection for extracted C record FooHandle.\""
    assert ast_string =~ "@type foo_handle_record() :: %{required(:ptr) => term(), required(:location) => Foo.Location.t()}"
  end

  test "exposes generated type declarations as module metadata" do
    assert GeneratedModule.__kinda_type_decls__() == [
             %TypeDecl{
               name: :foo_handle_record,
               source_record_name: "FooHandle",
               doc: "Typed projection for extracted C record FooHandle.",
               typespec: TypeSpecRef.map([])
             }
           ]
  end

  test "emits raw companion entries for kind-scoped generated functions" do
    {ast, _exports} =
      CodeGen.nif_ast(
        [%Kinda.CodeGen.KindDecl{module_name: Module.concat(__MODULE__, Kind)}],
        [],
        Module.concat(__MODULE__, GeneratedKinds),
        Forward
      )

    ast_string = ast |> then(&{:__block__, [], &1}) |> Macro.to_string()

    assert ast_string =~ "defmodule Raw"
    assert ast_string =~ ~s(def Elixir.Kinda.CodeGenTest.Kind.make)
    assert ast_string =~ ~s(apply(Kinda.CodeGenTest.GeneratedKinds)
  end
end
