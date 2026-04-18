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

  test "loads declaration manifests from elixir sidecars" do
    manifest = %{
      "version" => 1,
      "signature_manifest_version" => 3,
      "signature_manifest" => %{"version" => 3, "records" => [], "entries" => []},
      "nif_decls" => [],
      "type_decls" => []
    }

    path =
      System.tmp_dir!()
      |> Path.join("kinda-declaration-manifest-#{System.unique_integer([:positive])}.ex")

    File.write!(path, inspect(manifest, pretty: true, limit: :infinity, printable_limit: :infinity))

    try do
      assert DeclarationManifest.load!(path) == DeclarationManifest.from_manifest(manifest)
    after
      File.rm(path)
    end
  end

  test "build derives type declarations from the embedded signature contract" do
    declaration_manifest =
      DeclarationManifest.build(
        [],
        %{
          "version" => 5,
          "records" => [
            %{
              "name" => "Foo",
              "public_typespec" => %{
                "kind" => "map",
                "fields" => [
                  %{
                    "name" => "ctx",
                    "type" => %{
                      "kind" => "remote",
                      "module" => "Elixir.Foo.Context",
                      "type" => "t"
                    }
                  }
                ]
              }
            }
          ],
          "entries" => []
        }
      )

    assert DeclarationManifest.type_decls(declaration_manifest) == [
             %TypeDecl{
               name: :foo_record,
               source_record_name: "Foo",
               doc: "Typed projection for extracted C record Foo.",
               typespec: TypeSpecRef.map([{"ctx", TypeSpecRef.remote(Foo.Context)}])
             }
           ]
  end
end
