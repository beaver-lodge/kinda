defmodule Kinda.Wrapper.Extract do
  @moduledoc """
  Extracts a normalized wrapper manifest from a Clang AST tree.
  """

  alias Kinda.Wrapper.CType
  alias Kinda.Wrapper.Function
  alias Kinda.Wrapper.Manifest

  @spec from_clang_ast(map() | list()) :: Manifest.t()
  def from_clang_ast(ast) do
    %Manifest{
      functions:
        ast
        |> collect_functions()
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

  defp collect_children(node), do: node |> Map.get("inner", []) |> collect_functions()

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
