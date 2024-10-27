defmodule KindaExampleTest do
  use ExUnit.Case

  test "add in c" do
    assert 3 ==
             KindaExample.NIF.kinda_example_add(1, 2)
             |> KindaExample.Native.to_term()

    assert match?(
             %Kinda.CallError{message: "Fail to fetch argument #2", error_return_trace: _},
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
    assert Exception.message(e) =~ "Function clause error\n#{IO.ANSI.reset()}"

    err = catch_error(KindaExample.NIF."Elixir.KindaExample.NIF.StrInt.make"(1))
    # only test this on macOS, it will crash on Linux
    txt = Exception.message(err)

    if System.get_env("KINDA_DUMP_STACK_TRACE") == "1" do
      assert txt =~ "src/beam.zig"
      assert txt =~ "kinda_example/native/zig-src/main.zig"
    else
      assert txt =~ "to see the full stack trace, set KINDA_DUMP_STACK_TRACE=1"
    end

    assert match?(%Kinda.CallError{message: "Function clause error", error_return_trace: _}, err)

    assert KindaExample.NIF."Elixir.KindaExample.NIF.StrInt.make"("1")
           |> KindaExample.NIF."Elixir.KindaExample.NIF.CInt.primitive"() ==
             1
  end
end
