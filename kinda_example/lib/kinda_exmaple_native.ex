defmodule KindaExample.Native do
  def check!(ref) do
    case ref do
      {:error, e} ->
        raise e

      ref ->
        ref
    end
  end

  def to_term(%mod{ref: ref}) do
    forward(mod, :primitive, [ref])
  end

  def forward(
        element_kind,
        kind_func_name,
        args
      ) do
    apply(KindaExample.NIF, Module.concat(element_kind, kind_func_name), args)
    |> check!()
  end
end
