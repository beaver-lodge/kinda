defmodule Kinda.TestPolicy do
  @moduledoc false

  @type violation :: %{
          path: binary(),
          line: pos_integer() | nil,
          rule: :missing_async | :tmp_dir_called | :parse_error,
          module: binary() | nil
        }

  @spec check([binary()]) :: :ok | {:error, [violation()]}
  def check(paths) do
    files = discover(paths)
    violations = files |> Enum.flat_map(&check_file/1) |> Enum.sort_by(&sort_key/1)

    case violations do
      [] ->
        IO.puts("test policy OK (#{length(files)} files scanned)")
        :ok

      violations ->
        Enum.each(violations, &print_violation/1)
        {:error, violations}
    end
  end

  defp discover([]), do: discover(["."])

  defp discover(paths) do
    paths
    |> Enum.flat_map(&test_roots/1)
    |> Enum.flat_map(&source_files/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp test_roots(path) do
    cond do
      File.regular?(path) ->
        [path]

      Path.basename(Path.expand(path)) == "test" ->
        [path]

      Path.basename(Path.expand(path)) == "packages" ->
        Path.wildcard(Path.join([path, "*", "test"]))

      true ->
        [Path.join(path, "test") | Path.wildcard(Path.join([path, "packages", "*", "test"]))]
    end
  end

  defp source_files(path) do
    cond do
      File.regular?(path) and Path.extname(path) in [".ex", ".exs"] ->
        [path]

      File.dir?(path) ->
        Path.wildcard(Path.join([path, "**", "*.{ex,exs}"]))

      true ->
        []
    end
  end

  defp check_file(path) do
    case Code.string_to_quoted(File.read!(path), columns: true, token_metadata: true) do
      {:ok, ast} ->
        tmp_dir_violations(ast, path) ++ async_violations(ast, path)

      {:error, {location, error, token}} ->
        [violation(path, location[:line], :parse_error, nil, "#{error}#{token}")]
    end
  end

  defp tmp_dir_violations(ast, path) do
    walk(ast, [], fn
      {{:., dot_meta, [system, function]}, call_meta, arguments}, violations
      when function in [:tmp_dir, :tmp_dir!] and arguments == [] ->
        if system_module?(system) do
          line = call_meta[:line] || dot_meta[:line]
          [violation(path, line, :tmp_dir_called, nil) | violations]
        else
          violations
        end

      _node, violations ->
        violations
    end)
  end

  defp async_violations(ast, path) do
    if String.ends_with?(path, "_test.exs") do
      ast
      |> modules()
      |> Enum.flat_map(fn {module_ast, body} ->
        case direct_ex_unit_uses(body) do
          [] ->
            []

          uses ->
            if Enum.any?(uses, &async?/1) do
              []
            else
              [{meta, _options} | _rest] = uses
              [violation(path, meta[:line], :missing_async, Macro.to_string(module_ast))]
            end
        end
      end)
    else
      []
    end
  end

  defp modules({:quote, _meta, _arguments}), do: []

  defp modules({:defmodule, _meta, [module_ast, [do: body]]}) do
    [{module_ast, body} | modules(body)]
  end

  defp modules(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.flat_map(&modules/1)
  end

  defp modules(list) when is_list(list), do: Enum.flat_map(list, &modules/1)
  defp modules(_other), do: []

  defp direct_ex_unit_uses({:quote, _meta, _arguments}), do: []
  defp direct_ex_unit_uses({:defmodule, _meta, _arguments}), do: []

  defp direct_ex_unit_uses({:use, meta, [module_ast | arguments]} = node) do
    own =
      if ex_unit_case?(module_ast) do
        [{meta, List.first(arguments)}]
      else
        []
      end

    own ++ children(node, &direct_ex_unit_uses/1)
  end

  defp direct_ex_unit_uses(node), do: children(node, &direct_ex_unit_uses/1)

  defp children(tuple, callback) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.flat_map(callback)
  end

  defp children(list, callback) when is_list(list), do: Enum.flat_map(list, callback)
  defp children(_other, _callback), do: []

  defp async?({_meta, options}) when is_list(options), do: Keyword.get(options, :async) == true
  defp async?(_use), do: false

  defp ex_unit_case?({:__aliases__, _meta, [:ExUnit, :Case]}), do: true
  defp ex_unit_case?(ExUnit.Case), do: true
  defp ex_unit_case?(_module), do: false

  defp system_module?({:__aliases__, _meta, [:System]}), do: true
  defp system_module?(System), do: true
  defp system_module?(_module), do: false

  defp walk({:quote, _meta, _arguments}, accumulator, _callback), do: accumulator

  defp walk(node, accumulator, callback) do
    accumulator = callback.(node, accumulator)

    cond do
      is_tuple(node) ->
        node |> Tuple.to_list() |> Enum.reduce(accumulator, &walk(&1, &2, callback))

      is_list(node) ->
        Enum.reduce(node, accumulator, &walk(&1, &2, callback))

      true ->
        accumulator
    end
  end

  defp violation(path, line, rule, module, detail \\ nil) do
    %{path: path, line: line, rule: rule, module: module, detail: detail}
  end

  defp sort_key(violation), do: {violation.path, violation.line || 0, violation.rule}

  defp print_violation(violation) do
    location = if violation.line, do: "#{violation.path}:#{violation.line}", else: violation.path
    module = if violation.module, do: " (#{violation.module})", else: ""
    detail = if violation.detail, do: ": #{violation.detail}", else: ""
    IO.puts(:stderr, "#{location}: #{violation.rule}#{module}#{detail}")
  end
end

case Kinda.TestPolicy.check(System.argv()) do
  :ok -> :ok
  {:error, _violations} -> System.halt(1)
end
