defmodule Kinda.CodeGen.TypeSpecRefTest do
  use ExUnit.Case, async: true

  alias Kinda.CodeGen.TypeSpecRef

  test "renders and serializes map typespec refs" do
    typespec =
      TypeSpecRef.map([
        ptr: TypeSpecRef.term(),
        location: TypeSpecRef.remote(Foo.Location)
      ])

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
end
