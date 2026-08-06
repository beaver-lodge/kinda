defmodule Kinda.CodeGen.TypeSpecRef do
  @moduledoc """
  A small embedded DSL describing typespecs in declaration manifests.

  Typespecs are plain terms: builtins (`:term`, `:integer`, ...), remote
  module types, lists, maps, tuples and unions. `to_quoted/1` lowers them into
  quoted Elixir typespecs, and `to_manifest/1` / `from_manifest/1` round-trip
  them through the JSON-compatible manifest format.
  """

  @type map_key() :: atom() | String.t()
  @type builtin() :: :term | :integer | :float | :boolean | :binary | :atom | :ok
  @type t() ::
          builtin()
          | {:remote, module(), atom()}
          | {:list, t()}
          | {:map, [{map_key(), t()}]}
          | {:tuple, [t()]}
          | {:union, [t()]}

  @spec term() :: :term
  def term, do: :term

  @spec integer() :: :integer
  def integer, do: :integer

  @spec float() :: :float
  def float, do: :float

  @spec boolean() :: :boolean
  def boolean, do: :boolean

  @spec binary() :: :binary
  def binary, do: :binary

  @spec atom() :: :atom
  def atom, do: :atom

  @spec ok() :: :ok
  def ok, do: :ok

  @spec remote(module(), atom()) :: {:remote, module(), atom()}
  def remote(module, type_name \\ :t), do: {:remote, module, type_name}

  @spec list(t()) :: {:list, t()}
  def list(inner), do: {:list, inner}

  @spec map([{map_key(), t()}]) :: {:map, [{map_key(), t()}]}
  def map(fields), do: {:map, fields}

  @spec tuple([t()]) :: {:tuple, [t()]}
  def tuple(elements), do: {:tuple, elements}

  @spec union([t()]) :: {:union, [t()]}
  def union(types), do: {:union, types}

  @spec to_quoted(t()) :: Macro.t()
  def to_quoted(:term), do: quote(do: term())
  def to_quoted(:integer), do: quote(do: integer())
  def to_quoted(:float), do: quote(do: float())
  def to_quoted(:boolean), do: quote(do: boolean())
  def to_quoted(:binary), do: quote(do: binary())
  def to_quoted(:atom), do: quote(do: atom())
  def to_quoted(:ok), do: quote(do: :ok)

  def to_quoted({:remote, module, type_name}) do
    quote(do: unquote(module).unquote(type_name)())
  end

  def to_quoted({:list, inner}) do
    quote(do: [unquote(to_quoted(inner))])
  end

  def to_quoted({:map, fields}) do
    {:%{}, [],
     Enum.map(fields, fn {name, type} ->
       {{:required, [], [normalize_map_key_for_typespec(name)]}, to_quoted(type)}
     end)}
  end

  def to_quoted({:tuple, elements}) do
    {:{}, [], Enum.map(elements, &to_quoted/1)}
  end

  def to_quoted({:union, [type]}), do: to_quoted(type)

  def to_quoted({:union, [head | tail]}) do
    Enum.reduce(tail, to_quoted(head), fn type, ast ->
      {:|, [], [ast, to_quoted(type)]}
    end)
  end

  @spec to_manifest(t()) :: map()
  def to_manifest(:term), do: %{"kind" => "builtin", "name" => "term"}
  def to_manifest(:integer), do: %{"kind" => "builtin", "name" => "integer"}
  def to_manifest(:float), do: %{"kind" => "builtin", "name" => "float"}
  def to_manifest(:boolean), do: %{"kind" => "builtin", "name" => "boolean"}
  def to_manifest(:binary), do: %{"kind" => "builtin", "name" => "binary"}
  def to_manifest(:atom), do: %{"kind" => "builtin", "name" => "atom"}
  def to_manifest(:ok), do: %{"kind" => "literal", "name" => "ok"}

  def to_manifest({:remote, module, type_name}) do
    %{
      "kind" => "remote",
      "module" => Atom.to_string(module),
      "type" => Atom.to_string(type_name)
    }
  end

  def to_manifest({:list, inner}) do
    %{"kind" => "list", "inner" => to_manifest(inner)}
  end

  def to_manifest({:map, fields}) do
    %{
      "kind" => "map",
      "fields" =>
        Enum.map(fields, fn {name, type} ->
          %{"name" => to_string(name), "type" => to_manifest(type)}
        end)
    }
  end

  def to_manifest({:tuple, elements}) do
    %{"kind" => "tuple", "elements" => Enum.map(elements, &to_manifest/1)}
  end

  def to_manifest({:union, types}) do
    %{"kind" => "union", "types" => Enum.map(types, &to_manifest/1)}
  end

  @spec from_manifest(map()) :: t()
  def from_manifest(%{"kind" => "builtin", "name" => "term"}), do: :term
  def from_manifest(%{"kind" => "builtin", "name" => "integer"}), do: :integer
  def from_manifest(%{"kind" => "builtin", "name" => "float"}), do: :float
  def from_manifest(%{"kind" => "builtin", "name" => "boolean"}), do: :boolean
  def from_manifest(%{"kind" => "builtin", "name" => "binary"}), do: :binary
  def from_manifest(%{"kind" => "builtin", "name" => "atom"}), do: :atom
  def from_manifest(%{"kind" => "literal", "name" => "ok"}), do: :ok

  def from_manifest(%{"kind" => "remote", "module" => module_name, "type" => type_name}) do
    {:remote, Module.concat([module_name]), String.to_atom(type_name)}
  end

  def from_manifest(%{"kind" => "list", "inner" => inner}) do
    {:list, from_manifest(inner)}
  end

  def from_manifest(%{"kind" => "map", "fields" => fields}) when is_list(fields) do
    {:map,
     Enum.map(fields, fn %{"name" => name, "type" => type} ->
       {name, from_manifest(type)}
     end)}
  end

  def from_manifest(%{"kind" => "tuple", "elements" => elements}) when is_list(elements) do
    {:tuple, Enum.map(elements, &from_manifest/1)}
  end

  def from_manifest(%{"kind" => "union", "types" => types}) when is_list(types) do
    {:union, Enum.map(types, &from_manifest/1)}
  end

  defp normalize_map_key_for_typespec(name) when is_atom(name), do: name
  defp normalize_map_key_for_typespec(name) when is_binary(name), do: String.to_atom(name)
end
