defmodule DotPrompt.Parser.Validator do
  @moduledoc """
  Walks the AST checking types, bounds, nesting depth, and params.
  """

  @max_nesting 3

  def validate(ast) do
    case collect_errors(ast.body, 0) do
      [] ->
        with :ok <- validate_params_declared(ast),
             :ok <- validate_fragments_declared(ast),
             :ok <- validate_fragments(ast) do
          {:ok, []}
        end

      errors ->
        {:error, Enum.join(errors, "; ")}
    end
  end

  defp validate_fragments(%{init: nil}), do: :ok

  defp validate_fragments(ast) do
    fragments = parse_fragment_declarations(ast.init)
    declarations = parse_param_declarations(ast.init)

    errors =
      Enum.reduce(fragments, [], fn {_name, spec}, acc ->
        from = Map.get(spec, :from)
        matchre = Map.get(spec, :matchre) || Map.get(spec, :matchRe)

        acc =
          if from && String.ends_with?(from, "/") do
            ["invalid_fragment_path: trailing slashes not allowed in '#{from}'" | acc]
          else
            acc
          end

        if matchre && String.starts_with?(matchre, "@") do
          var_name = matchre
          param_spec = Map.get(declarations, var_name)

          cond do
            is_nil(param_spec) ->
              ["unknown_variable: #{var_name} referenced in matchRe but not declared" | acc]

            param_spec.type != :enum ->
              [
                "invalid_matchre_type: matchRe requires enum variable, but #{var_name} is #{param_spec.type}"
                | acc
              ]

            true ->
              acc
          end
        else
          acc
        end
      end)

    if errors == [], do: :ok, else: {:error, Enum.join(Enum.reverse(errors), "; ")}
  end

  defp collect_errors(_nodes, depth) when depth > @max_nesting do
    ["nesting_exceeded: depth #{depth} exceeds maximum of #{@max_nesting}"]
  end

  defp collect_errors(nodes, depth) when is_list(nodes) do
    Enum.flat_map(nodes, fn node ->
      case node do
        {:if, _, _, then_nodes, elifs, else_node} ->
          branch_results =
            [{nil, else_node} | elifs]
            |> Enum.flat_map(fn {_, branch_nodes} ->
              collect_errors(branch_nodes || [], depth + 1)
            end)

          collect_errors(then_nodes || [], depth + 1) ++ branch_results

        {:case, _, branches} ->
          Enum.flat_map(branches, fn
            {_id, _label, nodes} -> collect_errors(nodes || [], depth + 1)
            {:if, _, _, _, _, _} = n -> collect_errors([n], depth + 1)
            _ -> []
          end)

        {:vary, nil, _branches} ->
          ["invalid_vary: vary requires an enum variable"]

        {:vary, _var, branches} ->
          Enum.flat_map(branches, fn
            {_id, _label, nodes} -> collect_errors(nodes || [], depth + 1)
            {:if, _, _, _, _, _} = n -> collect_errors([n], depth + 1)
            _ -> []
          end)

        _ ->
          []
      end
    end)
  end

  defp collect_errors(_, _), do: []

  def get_warnings(ast) do
    case validate(ast) do
      {:ok, warnings} -> warnings
      _ -> []
    end
  end

  def validate_params(params, declarations) do
    case validate_params_present(params, declarations) do
      :ok -> validate_params_types(params, declarations)
      error -> error
    end
  end

  defp validate_fragments_declared(ast) do
    declared_fragments = parse_fragment_declarations(ast.init) |> Map.keys() |> MapSet.new()

    {static_fragments, _dynamic_fragments} =
      extract_fragments_from_body(ast.body, [])
      |> Enum.reduce({[], []}, fn fragment, {static, dynamic} ->
        case fragment do
          {:static, path} -> {[path | static], dynamic}
          {:dynamic, path} -> {static, [path | dynamic]}
        end
      end)

    unknown_static =
      Enum.reject(static_fragments, fn raw ->
        name = raw |> String.trim_leading("{") |> String.trim_trailing("}")
        MapSet.member?(declared_fragments, name)
      end)

    if unknown_static == [] do
      :ok
    else
      {:error,
       "unknown_fragment: #{hd(unknown_static)} referenced but not declared in init block. Inline fragment declarations are no longer supported."}
    end
  end

  defp extract_fragments_from_body(nodes, acc) when is_list(nodes) do
    Enum.reduce(nodes, acc, fn node, current_acc ->
      case node do
        {:fragment_static, path} ->
          [{:static, path} | current_acc]

        {:fragment_dynamic, path} ->
          [{:dynamic, path} | current_acc]

        {:if, _var, _cond, then_nodes, elifs, else_node} ->
          branches = [then_nodes | [else_node | Enum.map(elifs, &elem(&1, 1))]]
          extract_fragments_from_body(branches, current_acc)

        {:case, _var, branches} ->
          extract_fragments_from_body(Enum.map(branches, &elem(&1, 2)), current_acc)

        {:vary, _var, branches} ->
          extract_fragments_from_body(Enum.map(branches, &elem(&1, 2)), current_acc)

        _ ->
          current_acc
      end
    end)
    |> Enum.uniq()
  end

  defp validate_params_declared(ast) do
    declarations = parse_param_declarations(ast.init)

    if declarations == %{} do
      :ok
    else
      case extract_vars_from_body(ast.body, []) do
        {:ok, used_vars} ->
          declared_set =
            declarations
            |> Map.keys()
            |> Enum.map(fn k -> String.trim_leading(k, "@") end)
            |> MapSet.new()

          unknown_vars = Enum.reject(used_vars, &MapSet.member?(declared_set, &1))

          if unknown_vars == [] do
            :ok
          else
            {:error, "unknown_variable: #{hd(unknown_vars)} referenced but not declared"}
          end

        {:error, _} = error ->
          error
      end
    end
  end

  defp extract_vars_from_body(nodes, acc) when is_list(nodes) do
    result =
      Enum.reduce_while(nodes, {:ok, acc}, fn node, {:ok, current_acc} ->
        case node do
          {:text, t} ->
            vars = Regex.scan(~r/@(\w+)/, t, capture: :all_but_first) |> List.flatten()
            {:cont, {:ok, current_acc ++ vars}}

          {:if, var, cond, then_nodes, elifs, else_node} ->
            var_name = String.trim_leading(var, "@")

            cond_vars =
              Regex.scan(~r/@(\w+)/, cond || "", capture: :all_but_first) |> List.flatten()

            branch_acc = [var_name | cond_vars] ++ current_acc
            all_branch_nodes = [then_nodes | [else_node | Enum.map(elifs, &elem(&1, 1))]]

            case extract_vars_from_body(all_branch_nodes, branch_acc) do
              {:ok, vars} -> {:cont, {:ok, vars}}
              error -> {:halt, error}
            end

          {:case, var, branches} ->
            var_name = String.trim_leading(var, "@")
            branch_nodes = Enum.map(branches, &elem(&1, 2))

            case extract_vars_from_body(branch_nodes, [var_name | current_acc]) do
              {:ok, vars} -> {:cont, {:ok, vars}}
              error -> {:halt, error}
            end

          {:vary, _, branches} ->
            branch_nodes = Enum.map(branches, &elem(&1, 2))

            case extract_vars_from_body(branch_nodes, current_acc) do
              {:ok, vars} -> {:cont, {:ok, vars}}
              error -> {:halt, error}
            end

          _ ->
            {:cont, {:ok, current_acc}}
        end
      end)

    case result do
      {:ok, vars} -> {:ok, Enum.uniq(vars)}
      error -> error
    end
  end

  def parse_param_declarations(nil), do: %{}

  def parse_param_declarations(%{params: params}) do
    Enum.into(params, %{}, fn {name, info} ->
      {name, parse_param_info(name, info)}
    end)
  end

  def parse_param_declarations(_), do: %{}

  defp parse_param_info(_name, info) when is_map(info) do
    raw_spec = Map.get(info, :type, "str")
    doc = Map.get(info, :doc)

    # Handle default value after : or =
    # We look for the last : or = that isn't inside brackets []
    {type_spec, default_val} = split_type_and_default(raw_spec)

    {type, constraints} = parse_type_spec(type_spec)

    # Int with range is compile-time (selection), basic int is runtime
    life =
      constraints[:lifecycle] ||
        if type == :int and constraints[:range], do: :compile, else: lifecycle(type)

    # Cast default value based on type and ensure booleans default to false
    final_default =
      case {type, default_val} do
        {:bool, nil} ->
          false

        {:bool, str} when str in ["true", "TRUE", "1"] ->
          true

        {:bool, str} when str in ["false", "FALSE", "0"] ->
          false

        {:int, str} when is_binary(str) ->
          case Integer.parse(str) do
            {n, ""} -> n
            _ -> str
          end

        {:list, str} when is_binary(str) ->
          str = str |> String.trim_leading("[") |> String.trim_trailing("]")

          if str == "" do
            []
          else
            str |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
          end

        _ ->
          default_val
      end

    %{
      type: type,
      raw: raw_spec,
      doc: doc || "",
      lifecycle: life,
      default: final_default,
      values: constraints[:values],
      range: constraints[:range]
    }
  end

  defp split_type_and_default(raw) do
    case find_top_level_separator(raw) do
      nil ->
        {String.trim(raw), nil}

      idx ->
        type_part = String.slice(raw, 0, idx) |> String.trim()
        def_part = String.slice(raw, idx + 1, String.length(raw)) |> String.trim()
        # Strip optional quotes
        def_part = def_part |> String.trim("\"") |> String.trim("'")
        {type_part, def_part}
    end
  end

  defp find_top_level_separator(raw) do
    chars = String.to_charlist(raw)
    do_find_separator(chars, 0, 0)
  end

  defp do_find_separator([], _idx, _depth), do: nil
  defp do_find_separator([?[ | rest], idx, depth), do: do_find_separator(rest, idx + 1, depth + 1)
  defp do_find_separator([?] | rest], idx, depth), do: do_find_separator(rest, idx + 1, depth - 1)
  defp do_find_separator([c | _rest], idx, 0) when c == ?=, do: idx
  defp do_find_separator([_ | rest], idx, depth), do: do_find_separator(rest, idx + 1, depth)

  defp parse_type_spec(spec) do
    spec = String.trim(spec)

    cond do
      Regex.match?(~r/^enum\s*\[(.*)\]$/, spec) ->
        [_, vals] = Regex.run(~r/^enum\s*\[(.*)\]$/, spec)
        values = Enum.map(String.split(vals, ","), &String.trim/1)
        {:enum, %{values: values}}

      Regex.match?(~r/^int\s*\[(\d+)\.\.(\d+)\]$/, spec) ->
        [_, min_s, max_s] = Regex.run(~r/^int\s*\[(\d+)\.\.(\d+)\]$/, spec)
        {:int, %{range: [String.to_integer(min_s), String.to_integer(max_s)]}}

      spec == "int" ->
        {:int, %{}}

      spec == "str" or spec == "string" ->
        {:str, %{}}

      spec == "bool" or spec == "boolean" ->
        {:bool, %{}}

      Regex.match?(~r/^list\s*\[(.*)\]$/, spec) ->
        [_, vals] = Regex.run(~r/^list\s*\[(.*)\]$/, spec)
        values = Enum.map(String.split(vals, ","), &String.trim/1)
        {:list, %{values: values}}

      true ->
        {:str, %{}}
    end
  end

  defp lifecycle(type) do
    case type do
      :str -> :runtime
      :int -> :runtime
      :list -> :compile
      :bool -> :compile
      _ -> :compile
    end
  end

  defp validate_params_present(params, declarations) do
    compile_params =
      declarations
      |> Enum.filter(fn {_, spec} -> Map.get(spec, :lifecycle) == :compile end)
      |> Enum.map(fn {k, _} -> k end)

    missing =
      Enum.filter(compile_params, fn name ->
        clean_name = String.trim_leading(name, "@")
        atom_name = to_existing_or_nil(clean_name)
        spec = Map.get(declarations, name)

        is_provided =
          (!is_nil(atom_name) and Map.has_key?(params, atom_name)) or
            Map.has_key?(params, clean_name) or
            Map.has_key?(params, name) or
            spec.type == :enum or
            spec.type == :list

        not is_provided
      end)

    if missing == [] do
      :ok
    else
      {:error, "missing_param: #{hd(missing)} required but not provided"}
    end
  end

  defp validate_params_types(params, declarations) do
    errors =
      Enum.reduce(declarations, [], fn {name, spec}, acc ->
        clean_name = String.trim_leading(name, "@")
        atom_name = to_existing_or_nil(clean_name)

        value =
          cond do
            not is_nil(atom_name) -> Map.get(params, atom_name)
            true -> Map.get(params, clean_name) || Map.get(params, name)
          end

        case validate_value(value, spec, name) do
          :ok -> acc
          {:error, reason} -> [reason | acc]
        end
      end)

    if errors == [] do
      :ok
    else
      {:error, Enum.join(errors, "; ")}
    end
  end

  defp validate_value(nil, %{lifecycle: :compile}, _name), do: :ok
  defp validate_value(nil, %{lifecycle: :runtime}, _name), do: :ok
  defp validate_value(_value, %{type: :str}, _name), do: :ok

  defp validate_value(value, %{type: :int, range: [min, max]}, name) do
    case value do
      n when is_integer(n) ->
        if n >= min and n <= max,
          do: :ok,
          else: {:error, "out_of_range: #{name} value #{n} out of range int[#{min}..#{max}]"}

      s when is_binary(s) ->
        case Integer.parse(s) do
          {n, ""} when n >= min and n <= max -> :ok
          _ -> {:error, "out_of_range: #{name} value #{s} out of range int[#{min}..#{max}]"}
        end

      nil ->
        :ok

      _ ->
        {:error, "invalid_type: #{name} expected int[#{min}..#{max}], got #{inspect(value)}"}
    end
  end

  defp validate_value(value, %{type: :int}, name) do
    cond do
      is_integer(value) -> :ok
      is_binary(value) and match?({_, ""}, Integer.parse(value)) -> :ok
      true -> {:error, "invalid_type: #{name} expected int, got #{inspect(value)}"}
    end
  end

  defp validate_value(value, %{type: :bool}, name) do
    if is_boolean(value) do
      :ok
    else
      {:error, "invalid_type: #{name} expected bool, got #{inspect(value)}"}
    end
  end

  defp validate_value(value, %{type: :enum, values: values}, name) do
    str_value = to_string(value)

    if str_value in values do
      :ok
    else
      {:error, "invalid_enum: #{name} value #{str_value} not in enum[#{Enum.join(values, ", ")}]"}
    end
  end

  defp validate_value(value, %{type: :list, values: enum_values}, name) do
    if is_list(value) do
      invalid = Enum.filter(value, fn item -> to_string(item) not in enum_values end)

      if invalid == [] do
        :ok
      else
        {:error,
         "invalid_enum: #{name} value(s) #{Enum.join(invalid, ", ")} not in list[#{Enum.join(enum_values, ", ")}]"}
      end
    else
      {:error, "invalid_type: #{name} expected list, got #{inspect(value)}"}
    end
  end

  defp validate_value(value, %{type: :list}, name) do
    if is_list(value) do
      :ok
    else
      {:error, "invalid_type: #{name} expected list, got #{inspect(value)}"}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  def parse_param_declarations_for_schema(nil), do: %{}

  def parse_param_declarations_for_schema(init_nodes) do
    parse_param_declarations(init_nodes)
  end

  def parse_def_block(nil), do: %{}

  def parse_def_block(%{def: def_map}) when is_map(def_map) do
    Enum.into(def_map, %{}, fn
      {:version, v} when is_integer(v) ->
        {:version, v}

      {:version, v} when is_binary(v) ->
        case Integer.parse(v) do
          {val, ""} -> {:version, val}
          _ -> {:version, v}
        end

      {:major, v} when is_integer(v) ->
        {:major, v}

      {:major, v} when is_binary(v) ->
        case Integer.parse(v) do
          {val, ""} -> {:major, val}
          _ -> {:major, v}
        end

      {k, v} ->
        {k, if(is_binary(v), do: v, else: to_string(v))}
    end)
  end

  def parse_def_block(_), do: %{}

  def parse_docs_block(nil), do: nil

  def parse_docs_block(%{docs: docs_text}), do: docs_text
  def parse_docs_block(_), do: nil

  def parse_fragment_declarations(nil), do: %{}

  def parse_fragment_declarations(%{fragments: fragments}) when is_map(fragments) do
    Enum.into(fragments, %{}, fn {name, info} ->
      raw_type = if is_map(info), do: Map.get(info, :type, "dynamic"), else: "dynamic"
      doc = if is_map(info), do: Map.get(info, :doc, ""), else: ""

      # Clean name from braces for consistent lookup
      clean_name =
        name
        |> to_string()
        |> String.trim_leading("{")
        |> String.trim_leading("{")
        |> String.trim_trailing("}")
        |> String.trim_trailing("}")

      # Type can include "from: path" and assembly rules
      {type, from, rules} = parse_fragment_type_and_rules(raw_type)

      # If "from" is specified, it's a static fragment reference (compile-time inline)
      # Otherwise default to "dynamic" (runtime interpolation)
      fragment_type =
        cond do
          from != nil and from != "" -> "static"
          type == "" or type == nil -> "dynamic"
          true -> type
        end

      source_path = if from, do: from, else: nil

      {clean_name,
       %{type: fragment_type, doc: doc}
       |> maybe_put(:from, source_path)
       |> maybe_put(:match, if(is_map(info), do: info[:match], else: nil))
       |> maybe_put(:matchRe, if(is_map(info), do: info[:matchRe] || info[:matchre], else: nil))
       |> maybe_put(:limit, if(is_map(info), do: info[:limit], else: nil))
       |> maybe_put(:order, if(is_map(info), do: info[:order], else: nil))
       |> Map.merge(rules)}
    end)
  end

  def parse_fragment_declarations(_), do: %{}

  defp parse_fragment_type_and_rules(raw) do
    # Split by lines to handle rules indented under the type
    lines = String.split(raw, ["\n", "\r\n"])
    [first | rest] = Enum.map(lines, &String.trim/1)

    {type, from} =
      case String.split(first, "from:", parts: 2) do
        [t, f] -> {String.trim(t), String.trim(f)}
        [t] -> {String.trim(t), nil}
      end

    rules =
      Enum.reduce(rest, %{}, fn line, acc ->
        case String.split(line, ":", parts: 2) do
          [rule, val] ->
            rule_val = String.trim(val)

            case to_existing_or_nil(String.trim(rule)) do
              nil -> acc
              rule_name -> Map.put(acc, rule_name, rule_val)
            end

          _ ->
            acc
        end
      end)

    {type, from, rules}
  end

  defp to_existing_or_nil(""), do: nil

  defp to_existing_or_nil(binary) when is_binary(binary) do
    try do
      String.to_existing_atom(binary)
    rescue
      ArgumentError -> nil
    end
  end

  defp to_existing_or_nil(_), do: nil
end
