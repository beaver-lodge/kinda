defmodule Kinda.ResourceKind do
  defmacro __using__(opts) do
    forward_module = Keyword.fetch!(opts, :forward_module)
    fields = Keyword.get(opts, :fields) || []
    gen_spec = Keyword.get(opts, :gen_spec, true)

    spec =
      if gen_spec do
        quote do
          @type t() :: %__MODULE__{}
        end
      end

    quote do
      defstruct [ref: nil] ++ unquote(fields)

      unquote(spec)

      def make(value) do
        %__MODULE__{
          ref: unquote(forward_module).forward(__MODULE__, "make", [value])
        }
      end

      defoverridable(make: 1)
    end
  end
end
