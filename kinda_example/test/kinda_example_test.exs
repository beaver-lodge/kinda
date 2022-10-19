defmodule KindaExampleTest do
  use ExUnit.Case

  test "add in c" do
    assert 3 ==
             KindaExample.NIF.kinda_example_add(1, 2)
             |> KindaExample.Native.to_term()
  end
end
