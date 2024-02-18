defmodule KindaExample.Native do
  def check!(ret) do
    ret |> dbg

    case ret do
      {:kind, mod, ref} when is_atom(mod) and is_reference(ref) ->
        struct!(mod, %{ref: ref})

      {:error, e} ->
        raise e

      _ ->
        ret
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
