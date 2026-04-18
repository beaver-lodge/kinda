%{
  "version" => 1,
  "signature_manifest_version" => 7,
  "signature_manifest" => %{
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
  },
  "nif_decls" => [
    %{
      "wrapper_name" => "invoke_from_manifest",
      "params" => ["engine"],
      "doc" => "Invokes from the unified declaration manifest.",
      "param_typespecs" => [%{"kind" => "builtin", "name" => "term"}],
      "return_typespec" => %{"kind" => "literal", "name" => "ok"},
      "dirty" => "dirty_io"
    }
  ],
  "type_decls" => [
    %{
      "name" => "bar_handle_record",
      "source_record_name" => "BarHandle",
      "doc" => "Typed projection for extracted C record BarHandle.",
      "typespec" => %{"kind" => "map", "fields" => []}
    }
  ]
}
