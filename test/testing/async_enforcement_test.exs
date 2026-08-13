defmodule Kinda.Testing.AsyncEnforcementTest do
  use ExUnit.Case, async: true

  test "every ExUnit module explicitly opts into async execution" do
    test_files =
      Path.wildcard("test/**/*_test.exs") ++ Path.wildcard("packages/*/test/**/*_test.exs")

    synchronous =
      Enum.reject(test_files, fn path ->
        path
        |> File.read!()
        |> String.contains?("use ExUnit.Case, async: true")
      end)

    assert synchronous == [], "tests missing `async: true`: #{Enum.join(synchronous, ", ")}"
  end
end
