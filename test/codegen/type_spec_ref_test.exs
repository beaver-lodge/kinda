defmodule Kinda.CodeGen.TypeSpecRefTest do
  use ExUnit.Case, async: true

  alias Kinda.CodeGen.TypeSpecRef

  test "renders and serializes map typespec refs" do
    typespec =
      TypeSpecRef.map(
        ptr: TypeSpecRef.term(),
        location: TypeSpecRef.remote(Foo.Location)
      )

    assert Macro.to_string(TypeSpecRef.to_quoted(typespec)) ==
             "%{required(:ptr) => term(), required(:location) => Foo.Location.t()}"

    assert TypeSpecRef.to_manifest(typespec) == %{
             "kind" => "map",
             "fields" => [
               %{
                 "name" => "ptr",
                 "type" => %{"kind" => "builtin", "name" => "term"}
               },
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
  end

  test "round-trips manifest-backed map typespec refs with string field names" do
    manifest = %{
      "kind" => "map",
      "fields" => [
        %{"name" => "name", "type" => %{"kind" => "builtin", "name" => "term"}},
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

    typespec = TypeSpecRef.from_manifest(manifest)

    assert typespec ==
             {:map,
              [
                {"name", :term},
                {"location", {:remote, Foo.Location, :t}}
              ]}

    assert Macro.to_string(TypeSpecRef.to_quoted(typespec)) ==
             "%{required(:name) => term(), required(:location) => Foo.Location.t()}"

    assert TypeSpecRef.to_manifest(typespec) == manifest
  end
end
