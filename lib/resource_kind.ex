defmodule Kinda.ResourceKind do
  @moduledoc """
  Defines a typed wrapper for a resource-backed native kind.

  `raw_module:` identifies the generated raw NIF surface. `codec:` selects the
  returned-value normalizer and defaults to `Kinda.Codec`.
  """

  defmacro __using__(opts) do
    raw_module = Keyword.fetch!(opts, :raw_module)
    codec = Keyword.get(opts, :codec, Kinda.Codec)
    fields = Keyword.get(opts, :fields) || []
    maker = Module.concat(__CALLER__.module, :make)
    spec = if Keyword.get(opts, :gen_spec, true), do: quote(do: @type(t() :: %__MODULE__{}))

    quote do
      defstruct [ref: nil] ++ unquote(fields)

      unquote(spec)

      def make(value) do
        %__MODULE__{ref: unquote(raw_module).unquote(maker)(Kinda.unwrap_ref(value)) |> unquote(codec).normalize()}
      end

      defoverridable(make: 1)
    end
  end
end
