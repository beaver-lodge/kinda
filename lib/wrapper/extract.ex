defmodule Kinda.Wrapper.Extract do
  @moduledoc """
  Extracts a normalized wrapper manifest from a Clang AST tree.
  """

  alias Kinda.Wrapper.CType
  alias Kinda.Wrapper.CField
  alias Kinda.Wrapper.CRecord
  alias Kinda.Wrapper.Function
  alias Kinda.Wrapper.Manifest

  @spec from_clang_ast(map() | list()) :: Manifest.t()
  def from_clang_ast(ast) do
    typedef_record_aliases = collect_typedef_record_aliases(ast)

    %Manifest{
      functions:
        ast
        |> collect_functions()
        |> Enum.sort_by(& &1.name),
      records:
        ast
        |> collect_records(typedef_record_aliases)
        |> dedupe_records()
        |> Enum.sort_by(& &1.name)
    }
  end

  defp collect_functions(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, &collect_functions/1)
  end

  defp collect_functions(%{"kind" => "FunctionDecl", "name" => name} = node) do
    params_with_types =
      node
      |> Map.get("inner", [])
      |> Enum.with_index()
      |> Enum.filter(fn {elem, _index} -> Map.get(elem, "kind") == "ParmVarDecl" end)
      |> Enum.map(fn {elem, index} ->
        {Map.get(elem, "name", "param_#{index}"), CType.from_clang_type(Map.get(elem, "type"))}
      end)

    [
      %Function{
        name: name,
        params: Enum.map(params_with_types, &elem(&1, 0)),
        param_ctypes: Enum.map(params_with_types, &elem(&1, 1)),
        arity: length(params_with_types),
        doc: extract_doc(node),
        return_ctype: CType.from_function_decl(node)
      }
      | collect_children(node)
    ]
  end

  defp collect_functions(node) when is_map(node), do: collect_children(node)
  defp collect_functions(_node), do: []

  defp collect_records(nodes, typedef_record_aliases) when is_list(nodes) do
    Enum.flat_map(nodes, &collect_records(&1, typedef_record_aliases))
  end

  defp collect_records(%{"kind" => "RecordDecl"} = node, typedef_record_aliases) do
    case record_from_node(node, typedef_record_aliases) do
      nil -> collect_record_children(node, typedef_record_aliases)
      record -> [record | collect_record_children(node, typedef_record_aliases)]
    end
  end

  defp collect_records(node, typedef_record_aliases) when is_map(node),
    do: collect_record_children(node, typedef_record_aliases)

  defp collect_records(_node, _typedef_record_aliases), do: []

  defp collect_record_children(node, typedef_record_aliases) do
    node
    |> Map.get("inner", [])
    |> collect_records(typedef_record_aliases)
  end

  defp collect_children(node), do: node |> Map.get("inner", []) |> collect_functions()

  defp record_from_node(%{} = node, typedef_record_aliases) do
    with true <- Map.get(node, "completeDefinition", false),
         name when is_binary(name) and name != "" <- record_name(node, typedef_record_aliases) do
      %CRecord{
        name: name,
        kind: record_kind(node),
        fields:
          node
          |> Map.get("inner", [])
          |> Enum.with_index()
          |> Enum.filter(fn {elem, _index} -> Map.get(elem, "kind") == "FieldDecl" end)
          |> Enum.map(fn {field, index} ->
            %CField{
              name: Map.get(field, "name", "field_#{index}"),
              ctype: CType.from_clang_type(Map.get(field, "type"))
            }
          end)
      }
    else
      _ -> nil
    end
  end

  defp record_name(node, typedef_record_aliases) do
    case Map.get(node, "name") do
      nil -> Map.get(typedef_record_aliases, Map.get(node, "id"))
      "" -> Map.get(typedef_record_aliases, Map.get(node, "id"))
      name -> name
    end
  end

  defp record_kind(node) do
    case Map.get(node, "tagUsed") do
      "struct" -> :struct
      "union" -> :union
      _ -> :record
    end
  end

  defp collect_typedef_record_aliases(ast) do
    collect_typedef_record_aliases(ast, %{})
  end

  defp collect_typedef_record_aliases(nodes, aliases) when is_list(nodes) do
    Enum.reduce(nodes, aliases, fn node, aliases_acc ->
      collect_typedef_record_aliases(node, aliases_acc)
    end)
  end

  defp collect_typedef_record_aliases(%{} = node, aliases) do
    aliases =
      case Map.get(node, "kind") do
        "TypedefDecl" ->
          typedef_name = Map.get(node, "name")

          node
          |> record_ids_from_node()
          |> Enum.reduce(aliases, fn record_id, acc ->
            Map.put_new(acc, record_id, typedef_name)
          end)

        _ ->
          aliases
      end

    Map.get(node, "inner", [])
    |> collect_typedef_record_aliases(aliases)
  end

  defp collect_typedef_record_aliases(_node, aliases), do: aliases

  defp record_ids_from_node(node) when is_list(node) do
    node
    |> Enum.flat_map(&record_ids_from_node/1)
    |> Enum.uniq()
  end

  defp record_ids_from_node(%{"ownedTagDecl" => %{"id" => id, "kind" => "RecordDecl"}} = node) do
    [id | record_ids_from_node(Map.get(node, "inner", []))]
  end

  defp record_ids_from_node(%{"decl" => %{"id" => id, "kind" => "RecordDecl"}} = node) do
    [id | record_ids_from_node(Map.get(node, "inner", []))]
  end

  defp record_ids_from_node(%{} = node), do: record_ids_from_node(Map.values(node))
  defp record_ids_from_node(_node), do: []

  defp dedupe_records(records) do
    records
    |> Enum.reduce(%{}, fn %CRecord{name: name} = record, acc ->
      Map.update(acc, name, record, fn existing ->
        if richer_record?(record, existing), do: record, else: existing
      end)
    end)
    |> Map.values()
  end

  defp richer_record?(left, right), do: length(left.fields) > length(right.fields)

  defp extract_doc(node) when is_map(node) do
    node
    |> Map.get("inner", [])
    |> Enum.find(&(Map.get(&1, "kind") == "FullComment"))
    |> case do
      nil ->
        nil

      full_comment ->
        full_comment
        |> render_comment_node()
        |> normalize_rendered_doc()
        |> case do
          "" -> nil
          doc -> doc
        end
    end
  end

  defp extract_doc(_node), do: nil

  defp render_comment_node(%{"kind" => "FullComment", "inner" => inner}) do
    inner
    |> Enum.map(&render_comment_node/1)
    |> Enum.reject(&blank_comment?/1)
    |> Enum.join("\n\n")
  end

  defp render_comment_node(%{"kind" => "ParagraphComment", "inner" => inner}) do
    inner
    |> Enum.map(&render_comment_node/1)
    |> Enum.reject(&blank_comment?/1)
    |> Enum.join("\n")
  end

  defp render_comment_node(%{"kind" => "ParamCommandComment", "param" => param} = node) do
    suffix =
      node
      |> nested_comment_text()
      |> case do
        "" -> ""
        body -> " " <> body
      end

    "@param #{param}#{suffix}"
  end

  defp render_comment_node(%{"kind" => "BlockCommandComment", "name" => name} = node) do
    suffix =
      node
      |> nested_comment_text()
      |> case do
        "" -> ""
        body -> " " <> body
      end

    "@#{name}#{suffix}"
  end

  defp render_comment_node(%{"kind" => "InlineCommandComment", "name" => name} = node) do
    suffix =
      node
      |> nested_comment_text()
      |> case do
        "" -> ""
        body -> " " <> body
      end

    "@#{name}#{suffix}"
  end

  defp render_comment_node(%{"kind" => kind, "text" => text})
       when kind in ["TextComment", "VerbatimBlockLineComment", "VerbatimLineComment"] do
    normalize_comment_text(text)
  end

  defp render_comment_node(%{"inner" => inner}) when is_list(inner) do
    inner
    |> Enum.map(&render_comment_node/1)
    |> Enum.reject(&blank_comment?/1)
    |> Enum.join("\n")
    |> normalize_comment_text()
  end

  defp render_comment_node(_node), do: ""

  defp nested_comment_text(node) do
    node
    |> Map.get("inner", [])
    |> Enum.map(&render_comment_node/1)
    |> Enum.reject(&blank_comment?/1)
    |> Enum.join(" ")
    |> normalize_comment_text()
  end

  defp normalize_comment_text(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp normalize_comment_text(_text), do: ""

  defp normalize_rendered_doc(text) when is_binary(text) do
    text
    |> String.split(~r/\n{2,}/, trim: true)
    |> Enum.map(&normalize_rendered_block/1)
    |> Enum.reject(&blank_comment?/1)
    |> format_doc_blocks()
    |> repair_clang_comment_breakage()
  end

  defp normalize_rendered_doc(_text), do: ""

  defp normalize_rendered_block(block) do
    block
    |> String.split("\n", trim: true)
    |> Enum.map(&normalize_comment_text/1)
    |> Enum.reject(&blank_comment?/1)
    |> build_comment_segments()
    |> render_comment_segments()
  end

  defp build_comment_segments(lines) do
    {segments, current} =
      Enum.reduce(lines, {[], nil}, fn line, {segments, current} ->
        cond do
          bullet_line?(line) ->
            {commit_segment(segments, current), %{kind: :bullet, text: line}}

          bullet_continuation?(current, line) ->
            {segments, %{current | text: current.text <> " " <> line}}

          paragraph_continuation?(current, line) ->
            {segments, %{current | text: current.text <> " " <> line}}

          true ->
            {commit_segment(segments, current), %{kind: :paragraph, text: line}}
        end
      end)

    commit_segment(segments, current)
  end

  defp render_comment_segments(segments) do
    segments
    |> Enum.chunk_by(& &1.kind)
    |> Enum.map(&render_comment_segment_chunk/1)
    |> Enum.reject(&blank_comment?/1)
    |> Enum.join("\n\n")
  end

  defp render_comment_segment_chunk([%{kind: :paragraph} | _] = chunk) do
    chunk
    |> Enum.map_join(" ", & &1.text)
    |> normalize_comment_text()
  end

  defp render_comment_segment_chunk([%{kind: :bullet} | _] = chunk) do
    bullets = Enum.map(chunk, & &1.text)

    if Enum.all?(bullets, &parameter_bullet?/1) do
      "Parameters:\n" <> Enum.join(bullets, "\n")
    else
      Enum.join(bullets, "\n")
    end
  end

  defp render_comment_segment_chunk(_chunk), do: ""

  defp format_doc_blocks(blocks) do
    {lead, params, returns, trailing} =
      Enum.reduce(blocks, {[], [], [], []}, fn block, {lead, params, returns, trailing} ->
        cond do
          String.starts_with?(block, "@param ") ->
            {lead, [String.replace_prefix(block, "@param ", "") | params], returns, trailing}

          String.starts_with?(block, "@return ") ->
            {lead, params, [String.replace_prefix(block, "@return ", "") | returns], trailing}

          String.starts_with?(block, "@returns ") ->
            {lead, params, [String.replace_prefix(block, "@returns ", "") | returns], trailing}

          params != [] or returns != [] ->
            {lead, params, returns, [block | trailing]}

          true ->
            {[block | lead], params, returns, trailing}
        end
      end)

    [Enum.reverse(lead) |> Enum.join("\n\n")]
    |> maybe_append(render_param_section(Enum.reverse(params)))
    |> maybe_append(render_return_section(Enum.reverse(returns)))
    |> maybe_append(Enum.reverse(trailing) |> Enum.join("\n\n"))
    |> Enum.reject(&blank_comment?/1)
    |> Enum.join("\n\n")
  end

  defp render_param_section([]), do: ""

  defp render_param_section(params) do
    rendered =
      Enum.map_join(params, "\n", fn param ->
        case String.split(param, ~r/\s+/, parts: 2) do
          [name, body] -> "- `#{name}`: #{body}"
          [name] -> "- `#{name}`"
        end
      end)

    "Parameters:\n#{rendered}"
  end

  defp render_return_section([]), do: ""

  defp render_return_section(returns) do
    rendered = Enum.join(returns, "\n\n")
    "Returns:\n#{rendered}"
  end

  defp repair_clang_comment_breakage(text) do
    text
    |> then(&Regex.replace(~r/`([[:alnum:]_]+)\s+to\s+`([[:alnum:]_]+)`/u, &1, "`\\1` to `\\2`"))
    |> then(&Regex.replace(~r/`(-[^`\n]+)"(?=\s)/u, &1, "`\\1`"))
  end

  defp maybe_append(parts, ""), do: parts
  defp maybe_append(parts, part), do: parts ++ [part]

  defp commit_segment(segments, nil), do: segments
  defp commit_segment(segments, segment), do: segments ++ [segment]

  defp bullet_line?(line), do: String.starts_with?(line, "- ")

  defp bullet_continuation?(%{kind: :bullet}, line),
    do: not bullet_line?(line) and String.match?(line, ~r/^[a-z(]/u)

  defp bullet_continuation?(_current, _line), do: false

  defp paragraph_continuation?(%{kind: :paragraph}, line), do: not bullet_line?(line)
  defp paragraph_continuation?(_current, _line), do: false

  defp parameter_bullet?(line), do: Regex.match?(~r/^- `[^`]+`:/u, line)

  defp blank_comment?(text) when is_binary(text), do: text == ""
  defp blank_comment?(_text), do: false
end
