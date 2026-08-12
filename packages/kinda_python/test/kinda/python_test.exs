defmodule Kinda.PythonTest do
  use ExUnit.Case, async: true

  alias Kinda.Python

  test "initializes the pinned CPython runtime once" do
    assert Python.initialized?()
    assert Python.version() =~ ~r/^3\.14\./
  end

  test "reports the regular or free-threaded build profile" do
    assert is_boolean(Python.free_threaded_build?())
  end
end
