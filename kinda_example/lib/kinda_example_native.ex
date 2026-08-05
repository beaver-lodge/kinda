defmodule KindaExample.Native do
  use Kinda.Codec

  def to_term(%mod{ref: ref}) do
    apply(KindaExample.NIF.Raw, Module.concat(mod, :primitive), [ref])
    |> normalize()
  end

  def to_term(value), do: value
end
