defmodule KindaExample.Native do
  def check!({:kind, mod, ref}) when is_atom(mod) and is_reference(ref) do
    struct!(mod, %{ref: ref})
  end

  def check!({:error, e}), do: raise(e)
  def check!(ret), do: ret

  def to_term(%mod{ref: ref}) do
    forward(mod, :primitive, [ref])
  end

  def forward(element_kind, kind_func_name, args) do
    apply(KindaExample.NIF, Module.concat(element_kind, kind_func_name), args)
    |> check!()
  end
end
