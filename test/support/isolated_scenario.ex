defmodule Kinda.Testing.IsolatedScenario do
  @moduledoc false

  def add(left, right), do: left + right
  def fail, do: raise("boom")
end
