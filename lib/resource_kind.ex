defmodule Kinda.ResourceKind do
  defmacro __using__(opts) do
    forward_module = Keyword.fetch!(opts, :forward_module)
    fields = Keyword.get(opts, :fields) || []
    generic = Keyword.get(opts, :generic) || false
    gen_spec = Keyword.get(opts, :gen_spec, true)

    quote bind_quoted: [
            forward_module: forward_module,
            fields: fields,
            generic: generic,
            gen_spec: gen_spec
          ] do
      kind = if generic, do: nil, else: __MODULE__
      defstruct [ref: nil, bag: MapSet.new(), kind: kind] ++ fields

      if gen_spec do
        @type t() :: %__MODULE__{}
      end

      def array(data, opts \\ []) do
        unquote(forward_module).array(data, __MODULE__, opts)
      end

      if generic do
        def make(kind, args) when is_atom(kind) and is_list(args) do
          %__MODULE__{
            ref: unquote(forward_module).forward(kind, "make", args),
            kind: kind
          }
        end
      else
        def make(value) do
          %__MODULE__{
            ref: unquote(forward_module).forward(__MODULE__, "make", [value])
          }
        end
      end
    end
  end
end
