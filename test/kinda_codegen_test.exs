defmodule Kinda.CodeGenTest do
  use ExUnit.Case, async: true

  alias Kinda.CodeGen
  alias Kinda.CodeGen.{DeclarationManifest, DeclarationSurfaces, NIFDecl, TypeDecl, TypeSpecRef}

  defmodule GeneratedDecls do
    @behaviour Kinda.CodeGen

    @impl true
    def kinds, do: []

    @impl true
    def declaration_manifest do
      DeclarationManifest.build(
        [
          %NIFDecl{
            wrapper_name: :invoke_dirty_cpu,
            params: [:engine],
            doc: "Invokes the engine.",
            dirty: :dirty_cpu
          }
        ],
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
      )
    end
  end

  defmodule ManifestBackedDecls do
    @behaviour Kinda.CodeGen

    @impl true
    def declaration_manifest, do: Path.expand("../fixtures/declaration_manifest.ex", __DIR__)
  end

  defmodule Codec do
    def normalize(value), do: value
  end

  defmodule CanonicalManifestDecls do
    @behaviour Kinda.CodeGen

    @impl true
    def declaration_manifest do
      DeclarationManifest.from_parts([], [], %{"version" => 8, "records" => [], "entries" => []})
    end
  end

  defmodule GeneratedModule do
    use Kinda.CodeGen,
      with: Kinda.CodeGenTest.GeneratedDecls,
      root: Kinda.CodeGenTest.GeneratedModule,
      codec: Kinda.CodeGenTest.Codec
  end

  defmodule ManifestBackedModule do
    use Kinda.CodeGen,
      with: Kinda.CodeGenTest.ManifestBackedDecls,
      root: Kinda.CodeGenTest.ManifestBackedModule,
      codec: Kinda.CodeGenTest.Codec
  end

  defmodule CanonicalManifestModule do
    use Kinda.CodeGen,
      with: Kinda.CodeGenTest.CanonicalManifestDecls,
      root: Kinda.CodeGenTest.CanonicalManifestModule,
      codec: Kinda.CodeGenTest.Codec
  end

  defmodule SplitRawModule do
    use Kinda.CodeGen,
      with: Kinda.CodeGenTest.GeneratedDecls,
      root: Kinda.CodeGenTest.SplitPublicModule,
      codec: Kinda.CodeGenTest.Codec,
      surface: :raw
  end

  defmodule SplitPublicModule do
    use Kinda.CodeGen,
      with: Kinda.CodeGenTest.GeneratedDecls,
      root: __MODULE__,
      raw_module: Kinda.CodeGenTest.SplitRawModule,
      codec: Kinda.CodeGenTest.Codec,
      surface: :public
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
        Codec
      )

    ast_string = ast |> then(&{:__block__, [], &1}) |> Macro.to_string()

    assert ast_string =~ ~s(@doc "Creates foo.)
    assert ast_string =~ "@spec mlirFoo(term()) :: integer()"
    assert ast_string =~ "defmodule Raw"
    assert ast_string =~ "def mlirFoo(ctx)"
    assert ast_string =~ "GeneratedDocs.Raw"
    assert ast_string =~ "GeneratedDocs.Raw.mlirFoo(Kinda.unwrap_ref(ctx))"
    assert ast_string =~ "Kinda.CodeGenTest.Codec.normalize()"
    refute ast_string =~ "apply("
  end

  test "can compile public wrappers and raw NIF stubs as separate surfaces" do
    assert function_exported?(SplitPublicModule, :invoke_dirty_cpu, 1)
    assert function_exported?(SplitRawModule, :invoke_dirty_cpu, 1)

    assert function_exported?(SplitPublicModule, :__kinda_declaration_surfaces__, 0)
    refute function_exported?(SplitRawModule, :__kinda_declaration_surfaces__, 0)
    refute Code.ensure_loaded?(SplitPublicModule.Raw)

    assert catch_error(SplitPublicModule.invoke_dirty_cpu(:engine)) == :not_loaded
  end

  test "split surfaces call the raw module directly and keep kind NIF names fully qualified" do
    root = Module.concat(__MODULE__, SplitRoot)
    raw_module = Module.concat(__MODULE__, SplitRaw)

    decls =
      CodeGen.nif_decls(
        [%Kinda.CodeGen.KindDecl{module_name: Module.concat(__MODULE__, Kind)}],
        [%NIFDecl{wrapper_name: :invoke, params: [:value]}],
        root
      )

    {public_ast, _public_exports} =
      CodeGen.public_nif_ast_from_decls(decls, raw_module, Codec)

    {raw_ast, _raw_exports} = CodeGen.raw_nif_ast_from_decls(decls)

    public_string = public_ast |> then(&{:__block__, [], &1}) |> Macro.to_string()
    raw_string = raw_ast |> then(&{:__block__, [], &1}) |> Macro.to_string()

    assert public_string =~ "SplitRaw.invoke(Kinda.unwrap_ref(value))"
    refute public_string =~ "defmodule Raw"
    refute public_string =~ "Kind.make"

    assert raw_string =~ "def invoke(value)"
    assert raw_string =~ ~s(def Elixir.Kinda.CodeGenTest.Kind.make)
    refute raw_string =~ "SplitRoot"
  end

  test "emits generated record type aliases from declaration manifests" do
    type_decls =
      DeclarationManifest.build(
        [],
        %{
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
        }
      )
      |> CodeGen.type_decls()

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

    assert ast_string =~
             "@type foo_handle_record() :: %{required(:ptr) => term(), required(:location) => Foo.Location.t()}"
  end

  test "exposes resolved declaration surfaces as module metadata" do
    surfaces = GeneratedModule.__kinda_declaration_surfaces__()

    assert %DeclarationSurfaces{
             source_declaration_manifest: %DeclarationManifest{},
             declaration_manifest: %DeclarationManifest{
               nif_decls: [
                 %NIFDecl{
                   wrapper_name: :invoke_dirty_cpu,
                   params: [:engine],
                   doc: "Invokes the engine.",
                   dirty: :dirty_cpu
                 }
               ],
               type_decls: [
                 %TypeDecl{
                   name: :foo_handle_record,
                   source_record_name: "FooHandle",
                   doc: "Typed projection for extracted C record FooHandle.",
                   typespec: typespec
                 }
               ],
               signature_manifest: %{
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
             }
           } = surfaces

    assert typespec == TypeSpecRef.map([])

    assert DeclarationSurfaces.type_decls(surfaces) == [
             %TypeDecl{
               name: :foo_handle_record,
               source_record_name: "FooHandle",
               doc: "Typed projection for extracted C record FooHandle.",
               typespec: TypeSpecRef.map([])
             }
           ]

    assert DeclarationSurfaces.signature_manifest(surfaces) == %{
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

  test "can source generated surfaces directly from declaration manifests" do
    expected_nif_name =
      Module.concat(Kinda.CodeGenTest.ManifestBackedModule, :invoke_from_manifest)

    surfaces = ManifestBackedModule.__kinda_declaration_surfaces__()

    assert DeclarationSurfaces.signature_manifest(surfaces) == %{
             "version" => 7,
             "records" => [
               %{
                 "name" => "BarHandle",
                 "kind" => "struct",
                 "public_typespec" => %{"kind" => "map", "fields" => []},
                 "fields" => []
               }
             ],
             "entries" => []
           }

    assert [
             %NIFDecl{
               wrapper_name: :invoke_from_manifest,
               nif_name: ^expected_nif_name,
               dirty: :dirty_io,
               return_typespec: :ok
             }
           ] = DeclarationSurfaces.nif_decls(surfaces)

    assert [
             %TypeDecl{
               name: :bar_handle_record,
               source_record_name: "BarHandle"
             }
           ] = DeclarationSurfaces.type_decls(surfaces)

    assert %DeclarationManifest{
             version: 1,
             signature_manifest_version: 7,
             signature_manifest: %{"version" => 7},
             nif_decls: [
               %NIFDecl{
                 wrapper_name: :invoke_from_manifest,
                 nif_name: ^expected_nif_name
               }
             ],
             type_decls: [
               %TypeDecl{name: :bar_handle_record}
             ]
           } = DeclarationSurfaces.declaration_manifest(surfaces)
  end

  test "uses the signature embedded in the declaration manifest" do
    assert CanonicalManifestModule.__kinda_declaration_surfaces__()
           |> DeclarationSurfaces.signature_manifest() == %{
             "version" => 8,
             "records" => [],
             "entries" => []
           }
  end

  test "declaration-manifest-backed generators do not need a parallel nif source callback" do
    assert [%NIFDecl{wrapper_name: :invoke_from_manifest}] =
             ManifestBackedModule.__kinda_declaration_surfaces__()
             |> DeclarationSurfaces.nif_decls()
  end

  test "formalizes resolved declaration surfaces through Kinda.CodeGen.DeclarationSurfaces" do
    expected_nif_name =
      Module.concat(Kinda.CodeGenTest.ManifestBackedModule, :invoke_from_manifest)

    assert %DeclarationSurfaces{
             source_declaration_manifest: %DeclarationManifest{},
             declaration_manifest: %DeclarationManifest{
               nif_decls: [
                 %NIFDecl{
                   wrapper_name: :invoke_from_manifest,
                   nif_name: ^expected_nif_name
                 }
               ],
               type_decls: [
                 %TypeDecl{name: :bar_handle_record}
               ]
             }
           } =
             DeclarationSurfaces.from_generator(
               Kinda.CodeGenTest.ManifestBackedDecls,
               Kinda.CodeGenTest.ManifestBackedModule
             )

    surfaces =
      DeclarationSurfaces.from_generator(
        Kinda.CodeGenTest.ManifestBackedDecls,
        Kinda.CodeGenTest.ManifestBackedModule
      )

    assert match?(
             %DeclarationManifest{},
             DeclarationSurfaces.source_declaration_manifest(surfaces)
           )

    assert DeclarationSurfaces.load_source(Kinda.CodeGenTest.ManifestBackedDecls) ==
             DeclarationSurfaces.source_declaration_manifest(surfaces)

    assert surfaces == ManifestBackedModule.__kinda_declaration_surfaces__()
  end

  test "emits raw companion entries for kind-scoped generated functions" do
    {ast, _exports} =
      CodeGen.nif_ast(
        [%Kinda.CodeGen.KindDecl{module_name: Module.concat(__MODULE__, Kind)}],
        [],
        Module.concat(__MODULE__, GeneratedKinds),
        Codec
      )

    ast_string = ast |> then(&{:__block__, [], &1}) |> Macro.to_string()

    assert ast_string =~ "defmodule Raw"
    assert ast_string =~ ~s(def Elixir.Kinda.CodeGenTest.Kind.make)

    assert ast_string =~
             ~s(Kinda.CodeGenTest.GeneratedKinds."Elixir.Kinda.CodeGenTest.Kind.make")

    refute ast_string =~ "apply("
  end
end
