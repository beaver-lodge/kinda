defmodule Kinda.Testing.IsolatedScenario do
  @moduledoc false

  def add(left, right), do: left + right

  def identity(value), do: value

  def noisy(value) do
    IO.write("native-style stdout noise")
    value
  end

  def fail, do: raise("boom")
end
