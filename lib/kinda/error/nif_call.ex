defmodule Kinda.CallError do
  @moduledoc """
  The exception raised when a generated NIF call fails.

  Native wrappers populate stable diagnostic fields in addition to the legacy
  `:message`. Generated public wrappers enrich argument failures with names,
  declared C types and the category of the original Elixir value.

  `KINDA_DUMP_STACK_TRACE=1` prints a native error return trace for internal
  native failures. Input decoding errors do not suggest a native trace because
  the caller already has enough information to correct the invocation.
  """

  @type t() :: %__MODULE__{
          message: String.t() | nil,
          reason: atom() | nil,
          phase: atom() | nil,
          function: atom() | String.t() | nil,
          arity: non_neg_integer() | nil,
          argument_index: pos_integer() | nil,
          argument_name: atom() | String.t() | nil,
          expected: String.t() | nil,
          actual: String.t() | nil,
          native_error: String.t() | nil
        }

  defexception [
    :message,
    :reason,
    :phase,
    :function,
    :arity,
    :argument_index,
    :argument_name,
    :expected,
    :actual,
    :native_error
  ]

  @doc false
  @spec enrich(t(), map(), [term()]) :: t()
  def enrich(%__MODULE__{} = error, context, arguments)
      when is_map(context) and is_list(arguments) do
    index = error.argument_index

    %{
      error
      | function: Map.get(context, :function, error.function),
        arity: Map.get(context, :arity, error.arity),
        argument_name: argument_metadata(context, :argument_names, index),
        expected: argument_metadata(context, :argument_types, index) || error.expected,
        actual: actual_argument(arguments, index, error.actual)
    }
  end

  @impl true
  def message(%__MODULE__{phase: :argument_decode} = error) do
    target = format_target(error)
    argument = format_argument(error)
    expectation = format_expectation(error)

    "#{target} rejected #{argument}#{expectation}"
  end

  def message(%__MODULE__{} = error) do
    message = error.message || "native call failed"

    message =
      case format_target(error) do
        "NIF call" -> message
        target -> "#{target} failed during #{format_phase(error.phase)}: #{message}"
      end

    if native_trace_relevant?(error) do
      message <> "\nto print the native error return trace, set KINDA_DUMP_STACK_TRACE=1"
    else
      message
    end
  end

  defp argument_metadata(_context, _key, nil), do: nil

  defp argument_metadata(context, key, index) do
    context
    |> Map.get(key, [])
    |> Enum.at(index - 1)
  end

  defp actual_argument(_arguments, nil, current), do: current

  defp actual_argument(arguments, index, _current),
    do: describe_argument(Enum.at(arguments, index - 1))

  defp describe_argument(nil), do: "nil"
  defp describe_argument(%module{}), do: inspect(module)
  defp describe_argument(value) when is_boolean(value), do: "boolean"
  defp describe_argument(value) when is_atom(value), do: "atom"
  defp describe_argument(value) when is_binary(value), do: "binary"
  defp describe_argument(value) when is_bitstring(value), do: "bitstring"
  defp describe_argument(value) when is_float(value), do: "float"
  defp describe_argument(value) when is_function(value), do: "function"
  defp describe_argument(value) when is_integer(value), do: "integer"
  defp describe_argument(value) when is_list(value), do: "list"
  defp describe_argument(value) when is_map(value), do: "map"
  defp describe_argument(value) when is_pid(value), do: "pid"
  defp describe_argument(value) when is_port(value), do: "port"
  defp describe_argument(value) when is_reference(value), do: "reference"
  defp describe_argument(value) when is_tuple(value), do: "tuple"

  defp format_target(%{function: function, arity: arity})
       when not is_nil(function) and is_integer(arity),
       do: "#{function}/#{arity}"

  defp format_target(_error), do: "NIF call"

  defp format_argument(%{argument_index: index, argument_name: name})
       when is_integer(index) and not is_nil(name),
       do: "argument ##{index} (#{name})"

  defp format_argument(%{argument_index: index}) when is_integer(index),
    do: "argument ##{index}"

  defp format_argument(_error), do: "an argument"

  defp format_expectation(%{expected: nil, actual: nil}), do: ""
  defp format_expectation(%{expected: expected, actual: nil}), do: ": expected #{expected}"
  defp format_expectation(%{expected: nil, actual: actual}), do: ": got #{actual}"

  defp format_expectation(%{expected: expected, actual: actual}),
    do: ": expected #{expected}, got #{actual}"

  defp format_phase(nil), do: "native execution"
  defp format_phase(phase), do: phase |> Atom.to_string() |> String.replace("_", " ")

  defp native_trace_relevant?(%{phase: phase, native_error: native_error}),
    do: phase in [:native, :return_encode] and not is_nil(native_error)
end
