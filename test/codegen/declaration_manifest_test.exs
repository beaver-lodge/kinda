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

  @tag :tmp_dir
  test "loads declaration manifests from elixir sidecars", %{tmp_dir: tmp_dir} do
    manifest = %{
      "version" => 1,
      "signature_manifest_version" => 3,
      "signature_manifest" => %{"version" => 3, "records" => [], "entries" => []},
      "nif_decls" => [],
      "type_decls" => []
    }

    path = Path.join(tmp_dir, "declaration_manifest.ex")

    File.write!(
      path,
      inspect(manifest, pretty: true, limit: :infinity, printable_limit: :infinity)
    )

    assert DeclarationManifest.load!(path) == DeclarationManifest.from_manifest(manifest)
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

  test "type declarations fall back to the embedded signature contract when omitted" do
    declaration_manifest =
      DeclarationManifest.from_manifest(%{
        "version" => 1,
        "signature_manifest_version" => 5,
        "signature_manifest" => %{
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
        },
        "nif_decls" => [],
        "type_decls" => []
      })

    assert DeclarationManifest.type_decls(declaration_manifest) == [
             %TypeDecl{
               name: :foo_record,
               source_record_name: "Foo",
               doc: "Typed projection for extracted C record Foo.",
               typespec: TypeSpecRef.map([{"ctx", TypeSpecRef.remote(Foo.Context)}])
             }
           ]
  end

  test "can update and merge declaration manifest surfaces through accessors" do
    declaration_manifest =
      DeclarationManifest.build(
        [
          %NIFDecl{wrapper_name: :foo, nif_name: Module.concat(Foo.Native, :foo), params: 1}
        ],
        %{"version" => 1, "records" => [], "entries" => []}
      )

    updated =
      declaration_manifest
      |> DeclarationManifest.put_signature_manifest(%{
        "version" => 2,
        "records" => [],
        "entries" => []
      })
      |> DeclarationManifest.put_type_decls([
        %TypeDecl{
          name: :foo_record,
          source_record_name: "Foo",
          doc: "Typed projection for extracted C record Foo.",
          typespec: TypeSpecRef.map([])
        }
      ])
      |> DeclarationManifest.merge_nif_decls([
        %NIFDecl{wrapper_name: :foo, nif_name: Module.concat(Foo.Native, :foo), params: 1},
        %NIFDecl{wrapper_name: :bar, nif_name: Module.concat(Bar.Native, :bar), params: 2}
      ])

    assert DeclarationManifest.signature_manifest_version(updated) == 2

    assert DeclarationManifest.nif_decls(updated) == [
             %NIFDecl{wrapper_name: :foo, nif_name: Module.concat(Foo.Native, :foo), params: 1},
             %NIFDecl{wrapper_name: :bar, nif_name: Module.concat(Bar.Native, :bar), params: 2}
           ]

    assert DeclarationManifest.type_decls(updated) == [
             %TypeDecl{
               name: :foo_record,
               source_record_name: "Foo",
               doc: "Typed projection for extracted C record Foo.",
               typespec: TypeSpecRef.map([])
             }
           ]
  end
end
