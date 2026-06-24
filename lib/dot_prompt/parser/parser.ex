defmodule DotPrompt.Parser.Parser do
  @moduledoc """
  Builds an AST from tokens.
  """

  def parse(tokens) do
    case parse_top_level(tokens, %{init: nil, body: []}) do
      {:error, _} = error -> error
      {state, _remaining} -> {:ok, state}
    end
  end

  defp parse_top_level([], state), do: {state, []}

  defp parse_top_level([token | rest], state) do
    case token.type do
      :block_start when token.value == "init" ->
        case parse_init_block(rest, %{def: %{}, params: %{}, fragments: %{}, docs: nil}) do
          {:ok, init_metadata, remaining} ->
            parse_top_level(remaining, %{state | init: init_metadata})

          {:error, _} = err ->
            err
        end

      _ ->
        case parse_nodes([token | rest], [], "@top") do
          {:error, _} = err ->
            err

          {body_ast, remaining} ->
            if remaining == [token | rest] do
              # parse_nodes didn't consume anything, probably an unmatched end
              if token.type == :block_end do
                if token.value in ["init", "docs", "response", "system", "user", "context"] do
                  parse_top_level(rest, state)
                else
                  {:error, "mismatched_end: unexpected end #{token.value} at top level"}
                end
              else
                # treat as text and continue
                val = token.value || ""
                parse_top_level(rest, %{state | body: state.body ++ [{:text, val}]})
              end
            else
              parse_top_level(remaining, %{state | body: state.body ++ body_ast})
            end
        end
    end
  end

  defp parse_init_block([], _acc), do: {:error, "Unexpected EOF in init"}

  defp parse_init_block([token | rest], acc) do
    case token.type do
      :block_end when token.value == "init" ->
        {:ok, acc, rest}

      :init_item when token.value == "version" ->
        handle_version_token(token, rest, acc)

      :init_item ->
        new_def = Map.put(acc.def, safe_to_atom(token.value), token.meta)
        parse_init_block(rest, %{acc | def: new_def})

      :case_label ->
        handle_case_label_token(token, rest, acc)

      :param_def ->
        handle_param_def_token(token, rest, acc)

      :fragment_def ->
        handle_fragment_def_token(token, rest, acc)

      :block_start when token.value == "docs" ->
        handle_docs_token(token, rest, acc)

      _ ->
        parse_init_block(rest, acc)
    end
  end

  defp handle_version_token(token, rest, acc) do
    case Integer.parse(token.meta) do
      {val, ""} ->
        new_def = Map.put(acc.def, :version, val)
        new_params = Map.put(acc.params, "@version", %{type: token.meta, doc: nil})
        parse_init_block(rest, %{acc | def: new_def, params: new_params})

      _ ->
        new_def = Map.put(acc.def, :version, token.meta)
        new_params = Map.put(acc.params, "@version", %{type: token.meta, doc: nil})
        parse_init_block(rest, %{acc | def: new_def, params: new_params})
    end
  end

  defp handle_case_label_token(token, rest, acc) do
    {indented, remaining} = take_indented(rest, token.indent)
    acc = %{acc | def: Map.put(acc.def, safe_to_atom(token.value), token.meta || "")}

    case process_init_label(token.value, indented, acc) do
      {:ok, new_acc} -> parse_init_block(remaining, new_acc)
      {:error, _} = err -> err
    end
  end

  defp handle_param_def_token(token, rest, acc) do
    {indented, rest} = take_indented(rest, token.indent)
    {doc_cont, rest} = take_doc(rest)

    doc =
      cond do
        indented != [] -> Enum.map_join(indented, "\n", &token_to_string_raw/1)
        doc_cont != nil -> doc_cont
        true -> nil
      end

    new_params = Map.put(acc.params, token.value, %{type: token.meta, doc: doc})
    parse_init_block(rest, %{acc | params: new_params})
  end

  defp handle_fragment_def_token(token, rest, acc) do
    {indented, rest} = take_indented(rest, token.indent)
    {_doc_cont, rest} = take_doc(rest)

    meta =
      if indented == [] do
        token.meta
      else
        token.meta <> "\n" <> Enum.map_join(indented, "\n", &token_to_string_raw/1)
      end

    # Strip braces from fragment name for the map key
    key = token.value |> String.trim_leading("{") |> String.trim_trailing("}")
    new_fragments = Map.put(acc.fragments, key, %{type: meta, doc: nil})
    parse_init_block(rest, %{acc | fragments: new_fragments})
  end

  defp handle_docs_token(_token, rest, acc) do
    case parse_docs_block(rest, "") do
      {:error, _} = err -> err
      {docs_text, rest} -> parse_init_block(rest, %{acc | docs: docs_text})
    end
  end

  defp take_doc([%{type: :text} | rest]), do: take_doc(rest)
  defp take_doc([%{type: :doc, value: doc} | rest]), do: {doc, rest}
  defp take_doc(tokens), do: {nil, tokens}

  defp take_indented(tokens, base_indent) do
    take_indented_recursive(tokens, base_indent, [])
  end

  defp take_indented_recursive([token | rest], base_indent, acc) do
    if token.indent > base_indent and token.type != :block_end do
      take_indented_recursive(rest, base_indent, acc ++ [token])
    else
      {acc, [token | rest]}
    end
  end

  defp take_indented_recursive(tokens, _, acc), do: {acc, tokens}

  defp token_to_string(token) do
    case token.type do
      :text -> token.value
      :init_item -> String.duplicate(" ", token.indent) <> token.value <> ": " <> token.meta
      :param_def -> String.duplicate(" ", token.indent) <> token.value <> ": " <> token.meta
      :fragment_def -> String.duplicate(" ", token.indent) <> token.value <> ": " <> token.meta
      # For other types that might be indented in init
      _ -> String.duplicate(" ", token.indent) <> (token.value || "")
    end
  end

  defp token_to_string_raw(token) do
    case token.type do
      :text ->
        token.value

      type when type in [:init_item, :param_def, :fragment_def, :case_item, :case_label] ->
        if token.meta && token.meta != "" do
          token.value <> ": " <> token.meta
        else
          token.value || ""
        end

      _ ->
        token.value || ""
    end
  end

  defp safe_to_atom(k) do
    try do
      String.to_existing_atom(k)
    rescue
      ArgumentError -> k
    end
  end

  defp process_init_label("def", indented, acc) do
    new_acc =
      Enum.reduce(indented, acc, fn
        %{type: :init_item, value: k, meta: v}, a ->
          %{a | def: Map.put(a.def, safe_to_atom(k), v)}

        _, a ->
          a
      end)

    {:ok, new_acc}
  end

  defp process_init_label("params", indented, acc) do
    tokens = indented ++ [%DotPrompt.Parser.Lexer.Token{type: :block_end, value: "init"}]

    case parse_init_block(tokens, %{acc | params: %{}}) do
      {:ok, sub_acc, _} -> {:ok, %{acc | params: Map.merge(acc.params, sub_acc.params)}}
      {:error, _} = err -> err
    end
  end

  defp process_init_label("fragments", indented, acc) do
    tokens = indented ++ [%DotPrompt.Parser.Lexer.Token{type: :block_end, value: "init"}]

    case parse_init_block(tokens, %{acc | fragments: %{}}) do
      {:ok, sub_acc, _} -> {:ok, %{acc | fragments: Map.merge(acc.fragments, sub_acc.fragments)}}
      {:error, _} = err -> err
    end
  end

  defp process_init_label(_, _indented, acc), do: {:ok, acc}

  defp parse_docs_block([token | rest], acc) do
    case token.type do
      :block_end when token.value == "docs" -> {String.trim(acc), rest}
      :text -> parse_docs_block(rest, acc <> "\n" <> token.value)
      _ -> parse_docs_block(rest, acc)
    end
  end

  defp parse_response_block([token | rest], line) do
    case token.type do
      :block_end when token.value == "response" ->
        {String.trim(""), rest}

      :text ->
        content = token.value

        case parse_response_block(rest, line) do
          {:error, _} = err ->
            err

          {acc_content, rest} ->
            {content <> "\n" <> acc_content, rest}
        end

      _ ->
        parse_response_block(rest, line)
    end
  end

  defp parse_nodes([], acc, context) do
    if valid_context?(context),
      do: {Enum.reverse(acc), []},
      else: {:error, "unclosed_block: expected end #{context}"}
  end

  defp parse_nodes([token | rest], acc, context) do
    case token.type do
      :text ->
        handle_text_token(token, rest, acc, context)

      :condition when token.value.kind == "if" ->
        handle_if_token(token, rest, acc, context)

      :condition when token.value.kind == "elif" ->
        {Enum.reverse(acc), [token | rest]}

      :else ->
        {Enum.reverse(acc), [token | rest]}

      :block_start when token.value == "response" ->
        handle_response_token(token, rest, acc, context)

      :block_end ->
        handle_block_end_token(token, rest, acc, context)

      :case_start ->
        handle_case_token(token, rest, acc, context)

      :vary_start ->
        handle_vary_token(token, rest, acc, context)

      :fragment_static ->
        parse_nodes(rest, [{:fragment_static, token.value} | acc], context)

      :fragment_dynamic ->
        parse_nodes(rest, [{:fragment_dynamic, token.value} | acc], context)

      _ ->
        parse_nodes(rest, [{:text, token_to_string(token)} | acc], context)
    end
  end

  defp handle_text_token(token, rest, acc, context) do
    trimmed = String.trim(token.value)
    is_branch = trimmed != "" and Regex.match?(~r/^\w+:.*$/, trimmed)

    if context == "BRANCH_CONTENT" and is_branch do
      {Enum.reverse(acc), [token | rest]}
    else
      parse_nodes(rest, [{:text, token.value} | acc], context)
    end
  end

  defp handle_if_token(token, rest, acc, context) do
    case parse_if_chain([token | rest]) do
      {:error, _} = err ->
        err

      {if_node, rest} ->
        parse_nodes(rest, [if_node | acc], context)
    end
  end

  defp handle_response_token(token, rest, acc, context) do
    case parse_response_block(rest, token.line) do
      {:error, _} = err ->
        err

      {response_content, rest} ->
        parse_nodes(rest, [{:response, response_content, token.line} | acc], context)
    end
  end

  defp handle_block_end_token(token, rest, acc, context) do
    {token_var, context_var} =
      case {token.value, context} do
        {"@" <> tv, "@" <> cv} -> {tv, cv}
        {"if", "@" <> cv} -> {nil, cv}
        {"@" <> tv, _} -> {tv, nil}
        {_, "@" <> cv} -> {nil, cv}
        _ -> {nil, nil}
      end

    if context_var != nil and token_var != nil and token_var != context_var do
      {Enum.reverse(acc), [token | rest]}
    else
      handle_block_end(token, rest, acc, context)
    end
  end

  defp handle_case_token(token, rest, acc, context) do
    case parse_case_branches(rest, token.value) do
      {:error, _} = err -> err
      {branches, rest} -> parse_nodes(rest, [{:case, token.value, branches} | acc], context)
    end
  end

  defp handle_vary_token(token, rest, acc, context) do
    var = token.value

    case parse_case_branches(rest, var) do
      {:error, _} = err -> err
      {branches, rest} -> parse_nodes(rest, [{:vary, var, branches} | acc], context)
    end
  end

  defp parse_if_chain([token | rest]) do
    var = token.value.var

    case parse_nodes(rest, [], var) do
      {:error, _} = err ->
        err

      {then_nodes, rest} ->
        case parse_elif_else(rest, var) do
          {:error, _} = err ->
            err

          {elifs, else_node, rest} ->
            {{:if, var, token.value.cond, then_nodes, elifs, else_node}, rest}
        end
    end
  end

  defp parse_elif_else([%{type: :condition, value: %{kind: "elif"}} = token | rest], context) do
    case parse_nodes(rest, [], context) do
      {:error, _} = err ->
        err

      {then_nodes, rest} ->
        case parse_elif_else(rest, context) do
          {:error, _} = err -> err
          {elifs, else_node, rest} -> {[{token.value.cond, then_nodes} | elifs], else_node, rest}
        end
    end
  end

  defp parse_elif_else([%{type: :else} | rest], context) do
    var = context

    case parse_nodes(rest, [], var) do
      {:error, _} = err ->
        err

      {else_nodes, rest} ->
        case rest do
          [%{type: :block_end} = t | final_rest] ->
            trim = extract_var_name(var)

            if t.value == var or t.value == trim,
              do: {[], else_nodes, final_rest},
              else: {[], else_nodes, [t | final_rest]}

          [] ->
            {[], else_nodes, []}

          _ ->
            {[], else_nodes, rest}
        end
    end
  end

  defp parse_elif_else([%{type: :block_end} = t | rest], context) do
    if t.value == context, do: {[], nil, rest}, else: {[], nil, [t | rest]}
  end

  defp parse_elif_else(tokens, _context), do: {[], nil, tokens}

  defp handle_block_end(token, rest, acc, context) do
    context_var = extract_var(context)
    token_var = extract_var(token.value)

    cond do
      token.value == context ->
        {Enum.reverse(acc), rest}

      context_var != nil and token_var == context_var ->
        {Enum.reverse(acc), rest}

      context_var != nil and token.value == "if" ->
        {Enum.reverse(acc), rest}

      context_var != nil and token_var != nil ->
        {Enum.reverse(acc), [token | rest]}

      context == "BRANCH_CONTENT" ->
        {Enum.reverse(acc), [token | rest]}

      context == "@top" ->
        parse_nodes(rest, [{:text, "end " <> token.value} | acc], context)

      true ->
        {:error, "mismatched_end: expected end #{context}, got end #{token.value}"}
    end
  end

  defp parse_case_branches(tokens, context) do
    parse_case_recursive(tokens, context, [])
  end

  defp parse_case_recursive(tokens, context, acc) do
    parse_case_recursive_impl(tokens, context, acc)
  end

  defp parse_case_recursive_impl([%{type: :block_end, value: v} | rest], context, acc) do
    trim = extract_var_name(context)
    context_var = extract_var(context)

    cond do
      v == context or v == trim ->
        {Enum.reverse(acc), rest}

      context_var == nil and v == trim ->
        {Enum.reverse(acc), rest}

      true ->
        {:error, "mismatched_end: expected end #{context}, got end #{v}"}
    end
  end

  defp parse_case_recursive_impl([], context, _acc) do
    {:error, "unclosed_block: expected end #{context}"}
  end

  defp parse_case_recursive_impl(
         [%{type: :init_item, value: id, meta: label} | rest],
         context,
         acc
       ) do
    {content, remaining} = collect_until_case_boundary(rest, context)

    case parse_nodes(content, [], "BRANCH_CONTENT") do
      {:error, _} = err ->
        err

      {nodes, _} ->
        label_text = if label, do: String.trim(label), else: ""
        # Strip # prefix from case label
        label_text = String.trim_leading(label_text, "#") |> String.trim()
        nodes = if label_text != "", do: [{:text, label_text} | nodes], else: nodes
        parse_case_recursive(remaining, context, [{String.trim(id), label_text, nodes} | acc])
    end
  end

  defp parse_case_recursive_impl([%{type: :case_label, value: id} | rest], context, acc) do
    parse_case_recursive(rest, context, [{String.trim(id), "", []} | acc])
  end

  defp parse_case_recursive_impl([%{type: :text} = token | rest], context, acc) do
    line = String.trim(token.value)

    if Regex.match?(~r/^\w+:.*$/, line) do
      [id, label] = String.split(line, ":", parts: 2)
      {content, remaining} = collect_until_case_boundary(rest, context)

      case parse_nodes(content, [], "BRANCH_CONTENT") do
        {:error, _} = err ->
          err

        {nodes, _} ->
          label_text = String.trim(label)
          # Strip # prefix from case label
          label_text = String.trim_leading(label_text, "#") |> String.trim()
          nodes = if label_text != "", do: [{:text, label_text} | nodes], else: nodes
          parse_case_recursive(remaining, context, [{String.trim(id), label_text, nodes} | acc])
      end
    else
      parse_case_recursive(rest, context, acc)
    end
  end

  defp parse_case_recursive_impl(
         [%{type: :condition, value: %{kind: "if"}} = token | rest],
         context,
         acc
       ) do
    case parse_if_chain([token | rest]) do
      {:error, _} = err -> err
      {if_node, rest} -> parse_case_recursive(rest, context, [if_node | acc])
    end
  end

  defp parse_case_recursive_impl([%{type: :vary_start} = token | rest], context, acc) do
    var = token.value

    case parse_case_branches(rest, var) do
      {:error, _} = err -> err
      {branches, rest} -> parse_case_recursive(rest, context, [{:vary, var, branches} | acc])
    end
  end

  defp parse_case_recursive_impl([_ | rest], context, acc) do
    parse_case_recursive(rest, context, acc)
  end

  defp collect_until_case_boundary(tokens, context) do
    collect_until_case_boundary(tokens, context, [], 0)
  end

  defp collect_until_case_boundary([], _context, acc, _depth), do: {Enum.reverse(acc), []}

  defp collect_until_case_boundary([token | rest], context, acc, depth) do
    case token.type do
      :init_item when depth == 0 ->
        {Enum.reverse(acc), [token | rest]}

      :case_label when depth == 0 ->
        {Enum.reverse(acc), [token | rest]}

      type when type in [:case_start, :vary_start] ->
        collect_until_case_boundary(rest, context, [token | acc], depth + 1)

      :condition when token.value.kind == "if" ->
        collect_until_case_boundary(rest, context, [token | acc], depth + 1)

      :block_end ->
        context_var = extract_var(context)
        token_var = extract_var(token.value)
        trim = extract_var_name(context)

        cond do
          (token.value == context or (trim != nil and token.value == trim)) and depth == 0 ->
            {Enum.reverse(acc), [token | rest]}

          context_var != nil and token_var == context_var and depth == 0 ->
            {Enum.reverse(acc), [token | rest]}

          (token.value == "init" or token.value == "docs") and depth == 0 ->
            {Enum.reverse(acc), [token | rest]}

          true ->
            # Decrement depth if this block_end matches a block start we tracked
            # For simplicity, we just decrement if depth > 0
            new_depth = if depth > 0, do: depth - 1, else: 0
            collect_until_case_boundary(rest, context, [token | acc], new_depth)
        end

      _ ->
        collect_until_case_boundary(rest, context, [token | acc], depth)
    end
  end

  defp extract_var("@" <> name), do: name
  defp extract_var("if"), do: nil
  defp extract_var(_), do: nil

  defp extract_var_name(var) when is_binary(var) do
    if String.starts_with?(var, "@"), do: String.trim_leading(var, "@"), else: var
  end

  defp extract_var_name(_), do: nil

  defp valid_context?("@top"), do: true
  defp valid_context?("BRANCH_CONTENT"), do: true
  defp valid_context?(_), do: false
end
