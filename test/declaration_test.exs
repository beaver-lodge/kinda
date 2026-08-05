defmodule Kinda.DeclarationTest do
  use ExUnit.Case, async: true

  alias Kinda.CodeGen.{DeclarationManifest, DeclarationSurfaces, NIFDecl, TypeDecl, TypeSpecRef}
  alias Kinda.Declaration

  defmodule Fixture do
    alias Kinda.CodeGen.{DeclarationManifest, NIFDecl, TypeDecl, TypeSpecRef}

    def declaration_manifest do
      DeclarationManifest.from_parts(
        [
          %NIFDecl{
            wrapper_name: :demo,
            params: [:value],
            param_typespecs: [TypeSpecRef.term()],
            return_typespec: TypeSpecRef.ok()
          }
        ],
        [
          %TypeDecl{
            name: :demo_record,
            source_record_name: "DemoRecord",
            typespec: TypeSpecRef.map([{"value", TypeSpecRef.integer()}])
          }
        ],
        %{"version" => 1, "records" => [], "entries" => []}
      )
    end
  end

  test "provides a top-level facade over declaration surfaces" do
    surfaces = Declaration.from_generator(Fixture, Fixture.Generated)
    generated_demo = Module.concat(Fixture.Generated, :demo)

    assert %DeclarationSurfaces{
             source_declaration_manifest: %DeclarationManifest{},
             declaration_manifest: %DeclarationManifest{}
           } = surfaces

    assert Declaration.load_source(Fixture) == Fixture.declaration_manifest()
    assert Declaration.source_declaration_manifest(surfaces) == Fixture.declaration_manifest()

    assert [
             %NIFDecl{
               wrapper_name: :demo,
               nif_name: ^generated_demo,
               params: [:value],
               return_typespec: :ok
             }
           ] = Declaration.nif_decls(surfaces)

    assert [
             %TypeDecl{
               name: :demo_record,
               source_record_name: "DemoRecord",
               typespec: {:map, [{"value", :integer}]}
             }
           ] = Declaration.type_decls(surfaces)

    assert %{"version" => 1, "records" => [], "entries" => []} =
             Declaration.signature_manifest(surfaces)

    assert Declaration.declaration_manifest(surfaces) ==
             DeclarationSurfaces.declaration_manifest(surfaces)
  end
end
