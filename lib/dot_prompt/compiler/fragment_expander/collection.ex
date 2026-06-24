defmodule DotPrompt.Compiler.FragmentExpander.Collection do
  @moduledoc """
  Expands fragment collections via _index.prompt logic.
  """

  @spec expand(String.t(), map(), integer(), map(), integer(), map(), keyword()) ::
          {:ok, iodata(), MapSet.t(), map(), integer()} | {:error, String.t()}
  def expand(
        collection_path,
        params,
        indent \\ 0,
        acc_files \\ %{},
        acc_count \\ 0,
        rules \\ %{},
        opts \\ []
      ) do
    dir =
      collection_path
      |> String.trim_leading("{{")
      |> String.trim_leading("{")
      |> String.trim_trailing("}}")
      |> String.trim_trailing("}")
      |> String.trim_trailing("/")

    prompts_dir = DotPrompt.Helpers.prompts_dir(opts)
    full_path = Path.join(prompts_dir, dir)

    if File.dir?(full_path) do
      # Track directory for file add/remove
      dir_meta =
        case File.stat(full_path) do
          {:ok, %{mtime: t}} -> %{full_path => t}
          _ -> %{}
        end

      all_files =
        File.ls!(full_path)
        |> Enum.reject(&(&1 == "." or &1 == ".."))
        |> Enum.filter(fn file ->
          f_path = Path.join(full_path, file)
          String.ends_with?(file, ".prompt") or File.dir?(f_path)
        end)
        |> Enum.reject(&String.starts_with?(&1, "_"))

      matching_files = find_matching_files_with_rules(all_files, dir, params, rules)

      # If match rule was provided but found nothing, return "none" header per user request

      # match_rule is nil if no specific matching was requested
      match_rule = rules[:match] || rules[:matchRe] || rules[:matchre]

      if matching_files == [] and match_rule != nil do
        header_text =
          "\n[[section:frag:#{indent}:#{acc_count}:::fragment: #{dir} → none]]\n(none)\n[[/section]]\n"

        {:ok, [header_text], MapSet.new(), Map.merge(acc_files, dir_meta), acc_count + 1}
      else
        # Parallel compilation for maximum performance
        results =
          matching_files
          |> Task.async_stream(
            fn file ->
              name_only = String.replace_suffix(file, ".prompt", "")
              prompt_path = Path.join(dir, name_only)

              case DotPrompt.compile_to_iodata(prompt_path, params, indent: indent) do
                {:ok, content, _vary, used, item_files, _, _warnings, _contract, _major, _version,
                 _decls} ->
                  {:ok, content, used, item_files, name_only}

                {:error, details} ->
                  {:error, "fragment_compilation_failure: #{prompt_path} - #{details.message}"}
              end
            end,
            max_concurrency: System.schedulers_online() * 2,
            timeout: 5000
          )
          |> Enum.to_list()

        # Reduce results into iodata
        Enum.reduce_while(
          results,
          {[], MapSet.new(), Map.merge(acc_files, dir_meta), acc_count},
          fn
            {:ok, {:ok, content, used, item_files, name_only}}, {t_acc, u_acc, f_acc, c_acc} ->
              section = [
                "\n[[section:frag:",
                to_string(indent),
                ":",
                to_string(c_acc),
                ":::fragment: ",
                name_only,
                "]]\n",
                content,
                "\n[[/section]]\n"
              ]

              {:cont,
               {[t_acc, section], MapSet.union(u_acc, used), Map.merge(f_acc, item_files),
                c_acc + 1}}

            {:ok, {:error, reason}}, _ ->
              {:halt, {:error, reason}}

            {:exit, reason}, _ ->
              {:halt, {:error, "fragment_compilation_timeout_or_crash: #{inspect(reason)}"}}
          end
        )
        |> case do
          {:error, _} = err ->
            err

          {full_iodata, used_vars, merged_meta, final_count} ->
            {:ok, full_iodata, used_vars, merged_meta, final_count}
        end
      end
    else
      {:error, "collection_not_found: #{dir}"}
    end
  end

  defp find_matching_files_with_rules(all_files, dir, params, rules) do
    match_rule = rules[:match]
    match_re_rule = rules[:matchRe] || rules[:matchre]
    limit = if rules[:limit], do: String.to_integer(rules[:limit]), else: nil
    order = rules[:order]

    # Load match metadata for all files
    files_with_meta =
      Enum.map(all_files, fn file ->
        name_only = String.replace_suffix(file, ".prompt", "")
        prompt_path_for_schema = Path.join(dir, name_only)

        match_val =
          case DotPrompt.schema(prompt_path_for_schema) do
            {:ok, schema} -> Map.get(schema, :match)
            _ -> nil
          end

        {file, match_val}
      end)

    matched =
      cond do
        match_re_rule ->
          # Regex match
          pattern = interpolate_vars(match_re_rule, params)

          case Regex.compile(pattern) do
            {:ok, re} ->
              files_with_meta
              |> Enum.filter(fn {_f, m} -> m && Regex.match?(re, to_string(m)) end)
              |> Enum.map(&elem(&1, 0))

            {:error, _} ->
              []
          end

        match_rule == "all" ->
          all_files

        match_rule ->
          # Exact match or match against variable
          target_values = resolve_match_target(match_rule, params)

          files_with_meta
          |> Enum.filter(fn {_f, m} ->
            to_string(m) in target_values
          end)
          |> Enum.map(&elem(&1, 0))

        true ->
          # If no match rule was provided, default to all if there are no other rules,
          # otherwise it depends on the intent. Usually default to all for collections without match filters.
          all_files
      end

    # Apply suffix filter if provided
    matched =
      case rules[:suffix] do
        nil ->
          # When no suffix is specified, only match files that don't have any suffix
          # (i.e., the base file without _learn, _exercise, _scoring, etc.)
          Enum.filter(matched, fn file ->
            name = String.replace_suffix(file, ".prompt", "")
            # Check if the name ends with any known suffix pattern
            not Regex.match?(~r/_(learn|exercise|scoring|page)$/, name)
          end)

        suffix ->
          Enum.filter(matched, fn file ->
            name = String.replace_suffix(file, ".prompt", "")
            String.ends_with?(name, suffix)
          end)
      end

    # Apply order
    ordered =
      case order do
        "ascending" -> Enum.sort(matched)
        "descending" -> Enum.sort(matched, :desc)
        _ -> matched
      end

    # Apply limit
    if limit, do: Enum.take(ordered, limit), else: ordered
  end

  defp resolve_match_target("@" <> var_name, params) do
    var_atom =
      try do
        String.to_existing_atom(var_name)
      rescue
        ArgumentError -> nil
      end

    val =
      cond do
        var_atom && Map.has_key?(params, var_atom) -> Map.get(params, var_atom)
        Map.has_key?(params, var_name) -> Map.get(params, var_name)
        true -> nil
      end

    case val do
      nil -> []
      v when is_list(v) -> Enum.map(v, &to_string/1)
      v -> [to_string(v)]
    end
  end

  defp resolve_match_target(plain, _params), do: [plain]

  defp interpolate_vars(text, params) do
    Enum.reduce(params, text, fn {k, v}, acc ->
      String.replace(acc, "@#{k}", to_string(v))
    end)
  end
end
