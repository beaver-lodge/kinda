defmodule KindaExampleTest do
  use ExUnit.Case

  test "add in c" do
    assert 3 ==
             KindaExample.NIF.kinda_example_add(1, 2)
             |> KindaExample.Native.to_term()

    assert match?(
             %Kinda.CallError{message: :failToFetchArgumentResource, error_return_trace: _},
             catch_error(KindaExample.NIF.kinda_example_add(1, "2"))
           )
  end

  test "custom make" do
    assert KindaExample.Native.forward(
             KindaExample.NIF.CInt,
             :make,
             [100]
           )
           |> KindaExample.NIF."Elixir.KindaExample.NIF.CInt.primitive"() == 100

    e = catch_error(KindaExample.NIF."Elixir.KindaExample.NIF.StrInt.make"(1))
    assert match?("FunctionClauseError\n" <> _, Exception.message(e))

    assert match?(
             %Kinda.CallError{message: :FunctionClauseError, error_return_trace: _},
             catch_error(KindaExample.NIF."Elixir.KindaExample.NIF.StrInt.make"(1))
           )

    assert KindaExample.NIF."Elixir.KindaExample.NIF.StrInt.make"("1")
           |> KindaExample.NIF."Elixir.KindaExample.NIF.CInt.primitive"() ==
             1
  end
end
