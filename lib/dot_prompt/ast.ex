defmodule DotPrompt.AST do
  @moduledoc """
  AST node handlers for the DotPrompt compiler.

  ## Purpose

  Provides recursive compilation functions for each AST node type produced
  by the DotPrompt parser. Each `handle_*` function processes a specific
  node (text, if, case, vary, fragment) and returns compiled output along
  with tracking state (vary map, used variables, file metadata).

  ## Key Functions

  - `handle_text_node/3` — Interpolates `@param` references in raw text
  - `handle_if_node/6` — Compiles conditional branches and emits section
    annotations for traceability
  - `handle_case_node/4` — Compiles case/match branches with section
    annotations
  - `handle_vary_node/4` — Compiles all vary branches for at-runtime
    selection
  - `handle_static_fragment/3` — Expands static `{fragment}` includes
  - `handle_dynamic_fragment/3` — Expands dynamic `{{fragment}}` includes
  - `extract_vary_vars/1` — Collects all vary variable names from the AST

  ## Internal Use

  This module is called by `DotPrompt.Compiler.compile_ast/2` during the
  compilation phase. Each handler recursively compiles child nodes and
  accumulates state through a reduce-while pattern.
  """

  require Logger

  alias DotPrompt.Compiler.{CaseResolver, IfResolver}
  alias DotPrompt.Compiler.FragmentExpander.Collection, as: FragmentCollection
  alias DotPrompt.Compiler.FragmentExpander.Dynamic, as: FragmentDynamic
  alias DotPrompt.Compiler.FragmentExpander.Static, as: FragmentStatic
  alias DotPrompt.Helpers

  @doc false
  def handle_text_node(
        text,
        indent,
        context,
        {acc_text, acc_vary, acc_vars, acc_files, acc_count}
      ) do
    vars_in_text = Regex.scan(~r/@(\w+)/, text, capture: :all_but_first) |> List.flatten()
    new_vars = Enum.reduce(vars_in_text, acc_vars, &MapSet.put(&2, &1))

    interpolated_text =
      if context.opts[:skip_interpolation] do
        text
      else
        Enum.reduce(vars_in_text, text, fn var_name, acc_text ->
          case Helpers.get_param(context.params, var_name) do
            nil ->
              acc_text

            "" ->
              case Map.get(context.declarations || %{}, "@#{var_name}") do
                %{lifecycle: :runtime, default: ""} -> acc_text
                _ -> String.replace(acc_text, "@#{var_name}", "")
              end

            value ->
              String.replace(acc_text, "@#{var_name}", to_string(value))
          end
        end)
      end

    indented_text =
      interpolated_text
      |> String.split("\n")
      |> Enum.map(fn line -> if line == "", do: "\n", else: [indent, line, "\n"] end)

    {:cont, {[acc_text, indented_text], acc_vary, new_vars, acc_files, acc_count}}
  end

  @doc false
  def handle_if_node(
        var,
        cond,
        then_nodes,
        elifs,
        else_node,
        context,
        {acc_text, acc_vary, acc_vars, acc_files, acc_count}
      ) do
    var_name_str = String.trim_leading(var, "@")
    var_value = Helpers.get_param(context.params, var_name_str)
    current_vars = MapSet.put(acc_vars, var_name_str)

    {nodes_to_compile, val_label} =
      resolve_if_branch(var_value, cond, then_nodes, elifs, else_node)

    nodes_result =
      if nodes_to_compile do
        inner_context = %{
          context
          | vary_map: acc_vary,
            used_vars: current_vars,
            indent_level: context.indent_level + 1,
            files_meta: acc_files,
            section_count: acc_count + 1
        }

        DotPrompt.Compiler.compile_ast(nodes_to_compile, inner_context)
      else
        {"", acc_vary, current_vars, acc_files, acc_count}
      end

    case nodes_result do
      {:error, _} = err ->
        {:halt, err}

      {inner_text, inner_vary, inner_vars, inner_files, inner_count} ->
        result_text =
          build_if_result(
            var_name_str,
            var,
            val_label,
            context.declarations,
            context.indent_level,
            acc_count,
            inner_text
          )

        {:cont, {[acc_text, result_text], inner_vary, inner_vars, inner_files, inner_count}}
    end
  end

  defp resolve_if_branch(var_value, cond, then_nodes, elifs, else_node) do
    cond do
      IfResolver.resolve(var_value, cond) && then_nodes != [] ->
        {then_nodes, "true"}

      true ->
        case Enum.find(elifs, fn {c, nodes} -> IfResolver.resolve(var_value, c) && nodes != [] end) do
          nil -> if else_node && else_node != [], do: {else_node, "false"}, else: {nil, nil}
          {c, ns} -> {ns, to_string(c)}
        end
    end
  end

  defp build_if_result(
         _var_name_str,
         _var,
         nil,
         _declarations,
         _indent_level,
         _acc_count,
         inner_text
       ),
       do: inner_text

  defp build_if_result(
         var_name_str,
         var,
         val_label,
         declarations,
         indent_level,
         acc_count,
         inner_text
       ) do
    options =
      case Map.get(declarations || %{}, var_name_str) do
        %{type: :enum, values: values} -> Enum.join(values, ",")
        _ -> "true,false"
      end

    [
      "\n[[section:branch:",
      to_string(indent_level),
      ":",
      to_string(acc_count),
      ":",
      var_name_str,
      ":",
      options,
      ":",
      var,
      " → ",
      val_label,
      "]]\n",
      inner_text,
      "\n\n[[/section]]\n"
    ]
  end

  @doc false
  def handle_case_node(
        var,
        branches,
        context,
        {acc_text, acc_vary, acc_vars, acc_files, acc_count}
      ) do
    var_name_str = String.trim_leading(var, "@")
    var_value = Helpers.get_param(context.params, var_name_str)
    current_vars = MapSet.put(acc_vars, var_name_str)
    nodes_to_compile = CaseResolver.resolve(var_value, branches)
    match_label = find_case_match_label(branches, var_value)

    options =
      case Map.get(context.declarations || %{}, var_name_str) do
        %{values: vals} when is_list(vals) -> Enum.join(vals, ",")
        _ -> ""
      end

    result =
      if nodes_to_compile != [] do
        inner_context = %{
          context
          | vary_map: acc_vary,
            used_vars: current_vars,
            indent_level: context.indent_level + 1,
            files_meta: acc_files,
            section_count: acc_count + 1
        }

        DotPrompt.Compiler.compile_ast(nodes_to_compile, inner_context)
      else
        {"", acc_vary, current_vars, acc_files, acc_count}
      end

    case result do
      {:error, _} = err ->
        {:halt, err}

      {inner_text, inner_vary, inner_vars, inner_files, inner_count} ->
        section_header = [
          "\n[[section:case:",
          to_string(context.indent_level),
          ":",
          to_string(acc_count),
          ":",
          var_name_str,
          ":",
          options,
          ":",
          var,
          " → ",
          to_string(match_label),
          "]]\n"
        ]

        {:cont,
         {[acc_text, section_header, inner_text, "[[/section]]\n"], inner_vary, inner_vars,
          inner_files, inner_count}}
    end
  end

  defp find_case_match_label(branches, var_value) do
    Enum.find_value(branches, fn
      branch when is_tuple(branch) and tuple_size(branch) == 3 ->
        {id, lbl, _ns} = branch

        if to_string(id) == to_string(var_value),
          do: String.trim_leading(lbl, "#") |> String.trim(),
          else: nil

      {:if, var_name, _, _, _, _} = _branch ->
        if to_string(var_name) == to_string(var_value), do: to_string(var_name), else: nil

      _ ->
        nil
    end) || to_string(var_value)
  end

  @doc false
  def handle_vary_node(
        name,
        branches,
        context,
        {acc_text, acc_vary, acc_vars, acc_files, acc_count}
      ) do
    var_name_str = String.trim_leading(to_string(name), "@")
    current_vars = MapSet.put(acc_vars, var_name_str)
    options = Enum.map_join(branches, ",", fn {k, _, _} -> to_string(k) end)
    placeholder = ["[[vary:\"", to_string(name), "\"]]"]

    result =
      Enum.reduce_while(branches, {[], acc_vary, current_vars, acc_files, acc_count}, fn {id,
                                                                                            label,
                                                                                            nodes},
                                                                                           {acc_b,
                                                                                            var_acc,
                                                                                            vars_acc,
                                                                                            files_acc,
                                                                                            count_acc} ->
        inner_context = %{
          context
          | vary_map: var_acc,
            used_vars: vars_acc,
            indent_level: 0,
            files_meta: files_acc,
            section_count: 0
        }

        case DotPrompt.Compiler.compile_ast(nodes, inner_context) do
          {:error, _} = err ->
            {:halt, err}

          {branch_text, branch_vary, branch_vars, branch_files, _} ->
            branch_str = IO.iodata_to_binary(branch_text)

            {:cont,
             {acc_b ++ [{id, label, branch_str}], branch_vary, branch_vars, branch_files,
              count_acc}}
        end
      end)

    case result do
      {:error, _} = err ->
        {:halt, err}

      {compiled_branches, inner_vary, inner_vars, inner_files, inner_count} ->
        new_vary = Map.put(inner_vary, name, compiled_branches)

        section_header = [
          "\n[[section:vary:",
          to_string(context.indent_level),
          ":",
          to_string(acc_count),
          ":",
          "_vary_#{name}",
          ":",
          options,
          ":",
          name,
          "]]\n"
        ]

        {:cont,
         {[acc_text, section_header, placeholder, "\n\n[[/section]]\n"], new_vary, inner_vars,
          inner_files, inner_count}}
    end
  end

  @doc false
  def handle_static_fragment(path, context, {acc_text, acc_vary, acc_vars, acc_files, acc_count}) do
    name = path |> String.trim_leading("{") |> String.trim_trailing("}")

    case Map.get(context.fragment_defs, name) do
      %{type: type} = spec ->
        from = spec[:from] || name

        expand_static_fragment(
          name,
          from,
          type,
          spec,
          context,
          {acc_text, acc_vary, acc_vars, acc_files, acc_count}
        )

      _ ->
        {:halt,
         {:error, "fragment_not_declared: #{path} was used but not declared in init block"}}
    end
  end

  defp expand_static_fragment(
         name,
         from,
         type,
         spec,
         context,
         {acc_text, acc_vary, acc_vars, acc_files, acc_count}
       ) do
    indent = String.duplicate("  ", context.indent_level)

    if is_collection?(from, context.current_dir, context.opts) do
      resolved_from = resolve_collection_path(from, context.current_dir, context.opts)

      case FragmentCollection.expand(
             resolved_from,
             context.params,
             0,
             acc_files,
             acc_count,
             spec,
             context.opts
           ) do
        {:ok, inner_text, child_used, child_files, child_count} ->
          {:cont,
           {[acc_text, inner_text], acc_vary, MapSet.union(acc_vars, child_used), child_files,
            child_count}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    else
      is_static = type == "static" or String.contains?(type, "static")

      fragment_result =
        if is_static,
          do: FragmentStatic.expand(from, context.params, current_dir: context.current_dir),
          else: FragmentDynamic.expand(from, context.params)

      case fragment_result do
        {:ok, content_result, child_used, child_files} ->
          indented_content = Helpers.indent_content(content_result, indent)
          clean_name = String.replace_suffix(name, ".prompt", "")
          clean_from = String.replace_suffix(from, ".prompt", "")

          {:cont,
           {[
              acc_text,
              "\n[[section:frag:0:#{acc_count}:::fragment: ",
              clean_name,
              " → ",
              clean_from,
              "]]\n",
              indented_content,
              "\n[[/section]]\n"
            ], acc_vary, MapSet.union(acc_vars, child_used), Map.merge(acc_files, child_files),
            acc_count + 1}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end
  end

  defp is_collection?(path, current_dir, opts) do
    p_dir = Helpers.prompts_dir(opts)

    cond do
      String.starts_with?(path, "./") and current_dir != "" and current_dir != "." ->
        clean = String.slice(path, 2..-1//1)
        File.dir?(Path.join([p_dir, current_dir, clean]))

      current_dir != "" and current_dir != "." and
          File.dir?(Path.join([p_dir, current_dir, path])) ->
        true

      true ->
        String.ends_with?(path, "/") or
          (!String.contains?(path, ".") and File.dir?(Path.join(p_dir, path)))
    end
  end

  defp resolve_collection_path(path, current_dir, opts) do
    p_dir = Helpers.prompts_dir(opts)

    cond do
      String.starts_with?(path, "./") and current_dir != "" and current_dir != "." ->
        clean = String.slice(path, 2..-1//1)
        Path.join(current_dir, clean)

      current_dir != "" and current_dir != "." and
          File.dir?(Path.join([p_dir, current_dir, path])) ->
        Path.join(current_dir, path)

      File.dir?(Path.join(p_dir, path)) ->
        path

      true ->
        path
    end
  end

  @doc false
  def handle_dynamic_fragment(
        path,
        context,
        {acc_text, acc_vary, acc_vars, acc_files, acc_count}
      ) do
    name = path |> String.trim_leading("{{") |> String.trim_trailing("}}")

    case FragmentDynamic.expand(name, context.params) do
      {:ok, content, child_used, _child_files} ->
        {:cont,
         {[acc_text, content], acc_vary, MapSet.union(acc_vars, child_used), acc_files, acc_count}}
    end
  end

  @doc false
  def extract_vary_vars(nodes) when is_list(nodes) do
    Enum.reduce(nodes, MapSet.new(), fn node, acc ->
      case node do
        {:vary, name, branches} ->
          name_str = name |> to_string() |> String.trim_leading("@")

          branch_vars =
            Enum.reduce(branches, MapSet.new(), fn {_id, _label, sub_nodes}, a ->
              MapSet.union(a, extract_vary_vars(sub_nodes))
            end)

          acc |> MapSet.put(name_str) |> MapSet.union(branch_vars)

        {:if, _var, _cond, then_nodes, elifs, else_node} ->
          acc
          |> MapSet.union(extract_vary_vars(then_nodes))
          |> MapSet.union(
            Enum.reduce(elifs, MapSet.new(), fn {_, ns}, a ->
              MapSet.union(a, extract_vary_vars(ns))
            end)
          )
          |> MapSet.union(extract_vary_vars(else_node || []))

        {:case, _var, branches} ->
          acc
          |> MapSet.union(
            Enum.reduce(branches, MapSet.new(), fn {_id, _label, ns}, a ->
              MapSet.union(a, extract_vary_vars(ns))
            end)
          )

        _ ->
          acc
      end
    end)
  end

  def extract_vary_vars(_), do: MapSet.new()
end
