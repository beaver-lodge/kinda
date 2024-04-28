defmodule KindaExampleTest do
  use ExUnit.Case

  test "add in c" do
    assert 3 ==
             KindaExample.NIF.kinda_example_add(1, 2)
             |> KindaExample.Native.to_term()

    assert catch_error(KindaExample.NIF.kinda_example_add(1, "2")) ==
             :failToFetchArgumentResource
  end

  test "custom make" do
    assert KindaExample.Native.forward(
             KindaExample.NIF.CInt,
             :make,
             [100]
           )
           |> KindaExample.NIF."Elixir.KindaExample.NIF.CInt.primitive"() == 100

    assert catch_error(KindaExample.NIF."Elixir.KindaExample.NIF.StrInt.make"(1)) ==
             :FunctionClauseError

    assert KindaExample.NIF."Elixir.KindaExample.NIF.StrInt.make"("1")
           |> KindaExample.NIF."Elixir.KindaExample.NIF.CInt.primitive"() ==
             1
  end
end
