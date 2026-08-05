defmodule Kinda.Codec do
  @moduledoc """
  Normalizes values returned by raw NIF functions.

  A codec owns only the BEAM boundary representation. It does not select or
  dispatch native functions. Generated wrappers call their concrete raw NIF
  entrypoint first and then pass the result to `normalize/1`.
  """

  @callback normalize(term()) :: term() | no_return()

  defmacro __using__(_opts) do
    quote do
      @behaviour Kinda.Codec

      @impl true
      def normalize(value), do: Kinda.Codec.normalize(value)

      defoverridable normalize: 1
    end
  end

  @doc """
  Applies Kinda's default raw-result normalization.
  """
  @spec normalize(term()) :: term() | no_return()
  def normalize({:kind, mod, ref}) when is_atom(mod) do
    struct!(mod, %{ref: ref})
  end

  def normalize({{:kind, mod, ref}, metadata}) when is_atom(mod) do
    {struct!(mod, %{ref: ref}), metadata}
  end

  def normalize({:error, error}) do
    raise_error(error)
  end

  def normalize(value), do: value

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
