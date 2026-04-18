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
  @callback raw_call(kind_module(), kind_function(), args()) :: term() | no_return()
  @callback call(kind_module(), kind_function(), args()) :: term() | no_return()
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
      def raw_call(element_kind, kind_func_name, args) do
        Kinda.Forwarder.raw_call(@kinda_nif_module, element_kind, kind_func_name, args)
      end

      @impl true
      def call(element_kind, kind_func_name, args) do
        raw_call(element_kind, kind_func_name, args)
        |> check!()
      end

      @impl true
      def forward(element_kind, kind_func_name, args) do
        call(element_kind, kind_func_name, args)
      end

      @impl true
      def to_term(%mod{ref: ref}) do
        call(mod, :primitive, [ref])
      end

      def to_term(value), do: value

      defoverridable check!: 1, raw_call: 3, call: 3, forward: 3, to_term: 1
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
  Performs the raw kind-scoped NIF call without Elixir-side result
  normalization.
  """
  def raw_call(nif_module, element_kind, kind_func_name, args) when is_list(args) do
    function_name = Module.concat(element_kind, kind_func_name)
    raw_args = Kinda.unwrap_ref(args)

    try do
      apply(Module.concat(nif_module, Raw), function_name, raw_args)
    rescue
      UndefinedFunctionError ->
        apply(nif_module, function_name, raw_args)
    end
  end

  @doc """
  Performs a kind-scoped NIF call and applies the default `check!/1`
  normalization.
  """
  def call(nif_module, element_kind, kind_func_name, args) when is_list(args) do
    raw_call(nif_module, element_kind, kind_func_name, args)
    |> check!()
  end

  @doc """
  Compatibility entry for runtime modules that still expose only `forward/3`.
  New runtime code should prefer `call/3`.
  """
  def call_kind(runtime_module, element_kind, kind_func_name, args)
      when is_atom(runtime_module) do
    try do
      apply(runtime_module, :call, [element_kind, kind_func_name, args])
    rescue
      UndefinedFunctionError ->
        try do
          apply(runtime_module, :forward, [element_kind, kind_func_name, args])
        rescue
          UndefinedFunctionError ->
            raise ArgumentError,
                  "runtime module #{inspect(runtime_module)} must export call/3 or forward/3"
        end
    end
  end

  @doc """
  Normalizes the return value from a raw/public generated NIF wrapper call.
  """
  def normalize_result(ret, runtime_module) when is_atom(runtime_module) do
    try do
      apply(runtime_module, :check!, [ret])
    rescue
      UndefinedFunctionError ->
        ret
    end
  end

  @doc """
  Dispatches a raw generated NIF function and routes the return value through
  the runtime module's normalization path.
  """
  def invoke_public_nif(runtime_module, raw_module, raw_function, args)
      when is_atom(runtime_module) and is_atom(raw_module) and is_list(args) do
    apply(raw_module, raw_function, Kinda.unwrap_ref(args))
    |> normalize_result(runtime_module)
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
