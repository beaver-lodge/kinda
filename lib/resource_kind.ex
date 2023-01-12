defmodule Kinda.ResourceKind do
  defmacro __using__(opts) do
    forward_module = Keyword.fetch!(opts, :forward_module)
    fields = Keyword.get(opts, :fields) || []
    gen_spec = Keyword.get(opts, :gen_spec, true)

    quote bind_quoted: [
            forward_module: forward_module,
            fields: fields,
            gen_spec: gen_spec
          ] do
      defstruct [ref: nil, bag: MapSet.new()] ++ fields

      if gen_spec do
        @type t() :: %__MODULE__{}
      end

      def make(value) do
        %__MODULE__{
          ref: unquote(forward_module).forward(__MODULE__, "make", [value])
        }
      end
    end
  end
end
