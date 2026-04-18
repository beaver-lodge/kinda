defmodule Kinda.CodeGen.DeclarationManifestTest do
  use ExUnit.Case, async: true

  alias Kinda.CodeGen.{DeclarationManifest, NIFDecl, TypeDecl, TypeSpecRef}
  alias Kinda.Wrapper.CType

  test "round-trips machine-readable declaration manifests" do
    declaration_manifest =
      DeclarationManifest.from_parts(
        [
          %NIFDecl{
            wrapper_name: :foo,
            nif_name: Module.concat(Foo.Native, :foo),
            params: [:ctx],
            doc: "Creates foo.",
            param_ctypes: [%CType{spelling: "MlirContext", kind: :unknown}],
            return_ctype: %CType{spelling: "bool", kind: :bool},
            param_typespecs: [TypeSpecRef.remote(Foo.Context)],
            return_typespec: TypeSpecRef.boolean(),
            dirty: :dirty_cpu
          }
        ],
        [
          %TypeDecl{
            name: :foo_record,
            source_record_name: "Foo",
            doc: "Typed projection for extracted C record Foo.",
            typespec: TypeSpecRef.map([{"ctx", TypeSpecRef.remote(Foo.Context)}])
          }
        ],
        %{
          "version" => 3,
          "records" => [],
          "entries" => []
        }
      )

    manifest = DeclarationManifest.to_manifest(declaration_manifest)

    assert DeclarationManifest.from_manifest(manifest) == declaration_manifest
  end
end
