defmodule Kinda.Wrapper.Extract do
  @moduledoc """
  Extracts a normalized wrapper manifest from a Clang AST tree.
  """

  alias Kinda.Wrapper.{CType, CField, CRecord, Function, Manifest}

  @spec from_clang_ast(map() | list()) :: Manifest.t()
  def from_clang_ast(ast) do
    aliases = collect_typedef_record_aliases(ast)

    %Manifest{
      functions: ast |> collect(&function_from_node/1) |> Enum.sort_by(& &1.name),
      records: ast |> collect(&record_from_node(&1, aliases)) |> dedupe_records() |> Enum.sort_by(& &1.name)
    }
  end

  defp collect(nodes, emit) when is_list(nodes), do: Enum.flat_map(nodes, &collect(&1, emit))

  defp collect(%{} = node, emit), do: List.wrap(emit.(node)) ++ collect(Map.get(node, "inner", []), emit)

  defp collect(_node, _emit), do: []

  defp typed_children(node, kind, prefix) do
    for {child, index} <- Enum.with_index(Map.get(node, "inner", [])),
        Map.get(child, "kind") == kind do
      {Map.get(child, "name", "#{prefix}_#{index}"), CType.from_clang_type(Map.get(child, "type"))}
    end
  end

  defp function_from_node(%{"kind" => "FunctionDecl", "name" => name} = node) do
    {params, types} = node |> typed_children("ParmVarDecl", "param") |> Enum.unzip()

    %Function{
      name: name,
      params: params,
      param_ctypes: types,
      arity: length(params),
      doc: extract_doc(node),
      return_ctype: CType.from_function_decl(node)
    }
  end

  defp function_from_node(_node), do: nil

  defp record_from_node(%{"kind" => "RecordDecl"} = node, aliases) do
    with true <- Map.get(node, "completeDefinition", false),
         name when is_binary(name) and name != "" <- record_name(node, aliases) do
      fields =
        for {name, type} <- typed_children(node, "FieldDecl", "field"), do: %CField{name: name, ctype: type}

      %CRecord{name: name, kind: record_kind(node), fields: fields}
    else
      _ -> nil
    end
  end

  defp record_from_node(_node, _aliases), do: nil

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
    ast
    |> collect(fn
      %{"kind" => "TypedefDecl"} = node -> for id <- record_ids_from_node(node), do: {id, Map.get(node, "name")}
      _ -> []
    end)
    |> Enum.reduce(%{}, fn {id, name}, aliases -> Map.put_new(aliases, id, name) end)
  end

  defp record_ids_from_node(node) when is_list(node), do: node |> Enum.flat_map(&record_ids_from_node/1) |> Enum.uniq()

  defp record_ids_from_node(%{"ownedTagDecl" => %{"id" => id, "kind" => "RecordDecl"}} = node),
    do: [id | record_ids_from_node(Map.get(node, "inner", []))]

  defp record_ids_from_node(%{"decl" => %{"id" => id, "kind" => "RecordDecl"}} = node),
    do: [id | record_ids_from_node(Map.get(node, "inner", []))]

  defp record_ids_from_node(%{} = node), do: record_ids_from_node(Map.values(node))
  defp record_ids_from_node(_node), do: []

  defp dedupe_records(records) do
    records
    |> Enum.reduce(%{}, fn %CRecord{name: name} = record, acc ->
      Map.update(acc, name, record, fn existing ->
        if length(record.fields) > length(existing.fields), do: record, else: existing
      end)
    end)
    |> Map.values()
  end

  defp extract_doc(node) when is_map(node) do
    node
    |> Map.get("inner", [])
    |> Enum.find(&(Map.get(&1, "kind") == "FullComment"))
    |> render_comment_node()
    |> normalize_rendered_doc()
    |> case do
      "" -> nil
      doc -> doc
    end
  end

  defp render_comment_node(%{"kind" => "FullComment", "inner" => inner}), do: join_comments(inner, "\n\n")

  defp render_comment_node(%{"kind" => "ParagraphComment", "inner" => inner}), do: join_comments(inner, "\n")

  defp render_comment_node(%{"kind" => "ParamCommandComment", "param" => param} = node),
    do: command_comment("param #{param}", node)

  defp render_comment_node(%{"kind" => kind, "name" => name} = node)
       when kind in ["BlockCommandComment", "InlineCommandComment"], do: command_comment(name, node)

  defp render_comment_node(%{"kind" => kind, "text" => text})
       when kind in ["TextComment", "VerbatimBlockLineComment", "VerbatimLineComment"], do: normalize_comment_text(text)

  defp render_comment_node(%{"inner" => inner}) when is_list(inner),
    do: inner |> join_comments("\n") |> normalize_comment_text()

  defp render_comment_node(_node), do: ""

  defp join_comments(inner, separator) do
    inner |> Enum.map(&render_comment_node/1) |> Enum.reject(&blank_comment?/1) |> Enum.join(separator)
  end

  defp command_comment(name, node) do
    body = node |> Map.get("inner", []) |> join_comments(" ") |> normalize_comment_text()
    "@#{name}" <> if(body == "", do: "", else: " " <> body)
  end

  defp normalize_comment_text(text) when is_binary(text), do: text |> String.replace(~r/\s+/, " ") |> String.trim()

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
          bullet_line?(line) -> {commit_segment(segments, current), %{kind: :bullet, text: line}}
          continuation?(current, line) -> {segments, %{current | text: current.text <> " " <> line}}
          true -> {commit_segment(segments, current), %{kind: :paragraph, text: line}}
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

  defp render_comment_segment_chunk([%{kind: :paragraph} | _] = chunk),
    do: chunk |> Enum.map_join(" ", & &1.text) |> normalize_comment_text()

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
    sections =
      Enum.reduce(blocks, %{lead: [], params: [], returns: [], trailing: []}, fn block, acc ->
        {key, text} =
          case block do
            "@param " <> text -> {:params, text}
            "@return " <> text -> {:returns, text}
            "@returns " <> text -> {:returns, text}
            text -> {if(acc.params == [] and acc.returns == [], do: :lead, else: :trailing), text}
          end

        Map.update!(acc, key, &[text | &1])
      end)

    [
      sections.lead |> Enum.reverse() |> Enum.join("\n\n"),
      render_param_section(Enum.reverse(sections.params)),
      render_return_section(Enum.reverse(sections.returns)),
      sections.trailing |> Enum.reverse() |> Enum.join("\n\n")
    ]
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

  defp commit_segment(segments, nil), do: segments
  defp commit_segment(segments, segment), do: segments ++ [segment]

  defp bullet_line?(line), do: String.starts_with?(line, "- ")

  # Bullet starts are handled before continuations by build_comment_segments/1.
  defp continuation?(%{kind: :paragraph}, _line), do: true
  defp continuation?(%{kind: :bullet}, line), do: String.match?(line, ~r/^[a-z(]/u)
  defp continuation?(nil, _line), do: false

  defp parameter_bullet?(line), do: Regex.match?(~r/^- `[^`]+`:/u, line)

  defp blank_comment?(text) when is_binary(text), do: text == ""
  defp blank_comment?(_text), do: false
end
