defmodule Kinda.Forwarder do
  @moduledoc """
  Minimal public runtime adapter slice for `kinda`.

  This formalizes the three runtime operations that downstream adapters already
  need in practice:

  - `check!/1` for normalizing NIF return values
  - `forward/3` for dispatching kind-scoped functions through a NIF module
  - `to_term/1` for extracting BEAM values through a `primitive` path

  Consumers can `use Kinda.Forwarder` to get these defaults and then override
  or extend them for richer product-specific shapes such as arrays or opaque
  pointers.
  """

  @type kind_module() :: module()
  @type kind_function() :: atom() | binary()
  @type args() :: [term()]

  @callback check!(term()) :: term() | no_return()
  @callback forward(kind_module(), kind_function(), args()) :: term() | no_return()
  @callback to_term(term()) :: term() | no_return()

  defmacro __using__(opts) do
    nif_module = Keyword.fetch!(opts, :nif_module)

    quote bind_quoted: [nif_module: nif_module] do
      @behaviour Kinda.Forwarder
      @kinda_nif_module nif_module

      @impl true
      def check!(value), do: Kinda.Forwarder.check!(value)

      @impl true
      def forward(element_kind, kind_func_name, args) do
        Kinda.Forwarder.forward(@kinda_nif_module, element_kind, kind_func_name, args)
      end

      @impl true
      def to_term(%mod{ref: ref}) do
        forward(mod, :primitive, [ref])
      end

      def to_term(value), do: value

      defoverridable check!: 1, forward: 3, to_term: 1
    end
  end

  @doc """
  Normalizes the default result shapes emitted by generated wrappers.
  """
  def check!({:kind, mod, ref}) when is_atom(mod) do
    struct!(mod, %{ref: ref})
  end

  def check!({{:kind, mod, ref}, metadata}) when is_atom(mod) do
    {struct!(mod, %{ref: ref}), metadata}
  end

  def check!({:error, error}) do
    raise_error(error)
  end

  def check!(value), do: value

  @doc """
  Dispatches a kind-scoped function through the provided NIF module and applies
  the default `check!/1` normalization.
  """
  def forward(nif_module, element_kind, kind_func_name, args) when is_list(args) do
    apply(nif_module, Module.concat(element_kind, kind_func_name), args)
    |> check!()
  end

  defp raise_error(%{__struct__: _, __exception__: true} = error) do
    raise(error)
  end

  defp raise_error(message) when is_binary(message) do
    raise(Kinda.CallError, message: message)
  end

  defp raise_error(error) do
    raise(Kinda.CallError, message: inspect(error))
  end
end
