defmodule DotPrompt.Parser.Lexer do
  alias DotPrompt.Parser.Lexer.Token

  @moduledoc """
  Tokenizes .prompt files line by line.
  """

  def tokenize(content) do
    content
    |> String.split(["\r\n", "\n"])
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} -> tokenize_line(line, line_no) end)
  end

  defp tokenize_line(line, line_no) do
    {line, doc_token} = extract_doc(line, line_no)

    trimmed = String.trim_leading(line)
    indent = String.length(line) - String.length(trimmed)
    trimmed = String.trim_trailing(trimmed)

    tokens = tokenize_trimmed(trimmed, line, line_no, indent)

    tokens = Enum.map(tokens, &%{&1 | indent: indent})
    tokens ++ Enum.map(doc_token, &%{&1 | indent: indent})
  end

  defp extract_doc(line, line_no) do
    if String.contains?(line, "->") do
      [text, doc] = String.split(line, "->", parts: 2)
      {text, [%Token{type: :doc, value: String.trim(doc), line: line_no}]}
    else
      {line, []}
    end
  end

  defp tokenize_trimmed("", _line, line_no, _indent) do
    [%Token{type: :text, value: "", line: line_no}]
  end

  defp tokenize_trimmed(trimmed, original_line, line_no, _indent) do
    cond do
      trimmed == "" ->
        [%Token{type: :text, value: "", line: line_no}]

      String.starts_with?(trimmed, "#") ->
        []

      match_block_start(trimmed, line_no) ->
        match_block_start(trimmed, line_no)

      match_block_end(trimmed, line_no) ->
        match_block_end(trimmed, line_no)

      match_condition(trimmed, line_no) ->
        match_condition(trimmed, line_no)

      trimmed == "else" ->
        [%Token{type: :else, value: "else", line: line_no}]

      match_case_start(trimmed, line_no) ->
        match_case_start(trimmed, line_no)

      match_case_label(trimmed, line_no) ->
        match_case_label(trimmed, line_no)

      match_vary_start(trimmed, line_no) ->
        match_vary_start(trimmed, line_no)

      match_fragment_static(trimmed, line_no) ->
        match_fragment_static(trimmed, line_no)

      match_fragment_dynamic(trimmed, line_no) ->
        match_fragment_dynamic(trimmed, line_no)

      match_param_def(trimmed, line_no) ->
        match_param_def(trimmed, line_no)

      match_fragment_def(trimmed, line_no) ->
        match_fragment_def(trimmed, line_no)

      match_init_item(trimmed, line_no) ->
        match_init_item(trimmed, line_no)

      true ->
        [%Token{type: :text, value: original_line, line: line_no}]
    end
  end

  defp match_block_start(trimmed, line_no) do
    cond do
      String.starts_with?(trimmed, "init do") ->
        [%Token{type: :block_start, value: "init", line: line_no}]

      String.starts_with?(trimmed, "docs do") ->
        [%Token{type: :block_start, value: "docs", line: line_no}]

      String.starts_with?(trimmed, "response do") ->
        [%Token{type: :block_start, value: "response", line: line_no}]

      # Message section blocks (system, user, context)
      String.starts_with?(trimmed, "system do") ->
        [%Token{type: :block_start, value: "system", line: line_no}]

      String.starts_with?(trimmed, "user do") ->
        [%Token{type: :block_start, value: "user", line: line_no}]

      String.starts_with?(trimmed, "context do") ->
        [%Token{type: :block_start, value: "context", line: line_no}]

      true ->
        nil
    end
  end

  defp match_block_end(trimmed, line_no) do
    cond do
      Regex.match?(~r/^end\s+(@?[\w\d_]+)$/, trimmed) ->
        [_, value] = Regex.run(~r/^end\s+(@?[\w\d_]+)$/, trimmed)
        [%Token{type: :block_end, value: String.trim(value), line: line_no}]

      trimmed == "end" ->
        [%Token{type: :block_end, value: nil, line: line_no}]

      Regex.match?(~r/^end\s+init$/, trimmed) ->
        [%Token{type: :block_end, value: "init", line: line_no}]

      Regex.match?(~r/^end\s+docs$/, trimmed) ->
        [%Token{type: :block_end, value: "docs", line: line_no}]

      Regex.match?(~r/^end\s+response$/, trimmed) ->
        [%Token{type: :block_end, value: "response", line: line_no}]

      true ->
        nil
    end
  end

  defp match_condition(trimmed, line_no) do
    if Regex.match?(~r/^(if|elif)\s+(@\w+).*?\sdo$/, trimmed) do
      [_, kind, var, cond_str] = Regex.run(~r/^(if|elif)\s+(@\w+)\s*(.*?)\sdo$/, trimmed)

      [
        %Token{
          type: :condition,
          value: %{kind: kind, var: var, cond: String.trim(cond_str)},
          line: line_no
        }
      ]
    end
  end

  defp match_case_start(trimmed, line_no) do
    if Regex.match?(~r/^case @\w+ do/, trimmed) do
      [_, var] = Regex.run(~r/^case (@\w+) do/, trimmed)
      [%Token{type: :case_start, value: var, line: line_no}]
    end
  end

  defp match_case_label(trimmed, line_no) do
    if Regex.match?(~r/^[a-zA-Z_]\w*\s+do$/, trimmed) and
         trimmed not in ["vary do", "init do", "docs do", "response do", "else"] do
      [label] = Regex.run(~r/^([a-zA-Z_]\w*)\s+do$/, trimmed)
      [%Token{type: :case_label, value: label, line: line_no}]
    end
  end

  defp match_vary_start(trimmed, line_no) do
    cond do
      Regex.match?(~r/^vary\s+(@\w+)\s+do/, trimmed) ->
        [_, var] = Regex.run(~r/^vary\s+(@\w+) do/, trimmed)
        [%Token{type: :vary_start, value: var, line: line_no}]

      trimmed == "vary do" ->
        [%Token{type: :vary_start, value: nil, line: line_no}]

      true ->
        nil
    end
  end

  defp match_fragment_static(trimmed, line_no) do
    if Regex.match?(~r/^\{[\w\-\.\/]+\}$/, trimmed) and trimmed != "{response_contract}" do
      [%Token{type: :fragment_static, value: trimmed, line: line_no}]
    end
  end

  defp match_fragment_dynamic(trimmed, line_no) do
    if Regex.match?(~r/^\{\{[\w\-\.\/]+\}\}$/, trimmed) do
      [%Token{type: :fragment_dynamic, value: trimmed, line: line_no}]
    end
  end

  defp match_param_def(trimmed, line_no) do
    if Regex.match?(~r/^@[\w\d_]+:\s*(.*)$/, trimmed) do
      [_, name, type_info] = Regex.run(~r/^(@[\w\d_]+):\s*(.*)$/, trimmed)

      if name == "@version" do
        [%Token{type: :init_item, value: "version", meta: String.trim(type_info), line: line_no}]
      else
        [%Token{type: :param_def, value: name, meta: String.trim(type_info), line: line_no}]
      end
    end
  end

  defp match_fragment_def(trimmed, line_no) do
    if Regex.match?(~r/^\{{1,2}[\w\-\.\/]+\}{1,2}: ?/, trimmed) do
      [_, name, type_info] = Regex.run(~r/^(\{{1,2}[\w\-\.\/]+\}{1,2}):\s*(.*)$/, trimmed)
      [%Token{type: :fragment_def, value: name, meta: String.trim(type_info), line: line_no}]
    end
  end

  defp match_init_item(trimmed, line_no) do
    cond do
      Regex.match?(~r/^(def|params|fragments):\s*(.*)$/, trimmed) ->
        [_, key, val] = Regex.run(~r/^(def|params|fragments):\s*(.*)$/, trimmed)

        if String.trim(val) == "" do
          [%Token{type: :case_label, value: key, line: line_no}]
        else
          [%Token{type: :init_item, value: key, meta: String.trim(val), line: line_no}]
        end

      Regex.match?(~r/^([a-zA-Z0-9_\-\.]+):\s*(.*)$/, trimmed) ->
        [_, key, meta] = Regex.run(~r/^([a-zA-Z0-9_\-\.]+):\s*(.*)$/, trimmed)
        [%Token{type: :init_item, value: key, meta: String.trim(meta), line: line_no}]

      true ->
        nil
    end
  end
end
