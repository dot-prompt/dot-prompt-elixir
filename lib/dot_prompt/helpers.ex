defmodule DotPrompt.Helpers do
  @moduledoc false

  require Logger

  alias DotPrompt.Parser.{Lexer, Parser, Validator}
  alias DotPrompt.Compiler.ResponseCollector

  @doc false
  def prompts_dir(opts \\ []) do
    case Keyword.get(opts, :prompts_dir) || Application.get_env(:anantha_dot_prompt, :prompts_dir) do
      nil ->
        dir = "prompts"
        cwd = File.cwd!()

        cond do
          File.exists?(Path.join(cwd, dir)) ->
            Path.expand(Path.join(cwd, dir))

          File.exists?(Path.join([cwd, "dot_prompt", dir])) ->
            Path.expand(Path.join([cwd, "dot_prompt", dir]))

          File.exists?(Path.join([cwd, "..", "..", dir])) ->
            Path.expand(Path.join([cwd, "..", "..", dir]))

          true ->
            Path.expand(dir)
        end

      dir ->
        Path.expand(dir)
    end
  end

  @doc false
  def load_prompt_file_with_meta(name, major, current_dir \\ "", opts \\ []) do
    prompts_dir = prompts_dir(opts)
    name_str = to_string(name)
    {content, mtime, full_path} = resolve_prompt_path(prompts_dir, name_str, current_dir)

    if major && content do
      check_major_version(
        name,
        major,
        content,
        {content, mtime, full_path},
        prompts_dir,
        name_str
      )
    else
      if is_nil(content),
        do: raise("prompt_not_found: #{name}"),
        else: {content, mtime, full_path}
    end
  end

  defp resolve_prompt_path(prompts_dir, name_str, current_dir) do
    cond do
      String.starts_with?(name_str, "./") and current_dir != "" and current_dir != "." ->
        clean_name = String.slice(name_str, 2..-1//1)
        do_resolve(prompts_dir, Path.join(current_dir, clean_name))

      true ->
        res =
          if current_dir != "" and current_dir != "." do
            do_resolve(prompts_dir, Path.join(current_dir, name_str))
          else
            {nil, nil, nil}
          end

        if res == {nil, nil, nil} do
          do_resolve(prompts_dir, name_str)
        else
          res
        end
    end
  end

  defp do_resolve(prompts_dir, name_str) do
    safe_name =
      name_str
      |> String.trim_leading("/")
      |> String.replace("../", "")
      |> String.replace("./", "")

    path = Path.expand(Path.join(prompts_dir, safe_name))

    if String.starts_with?(path, prompts_dir) do
      cond do
        File.exists?(path) and !File.dir?(path) ->
          {File.read!(path), File.stat!(path).mtime, path}

        File.exists?(path <> ".prompt") ->
          p = path <> ".prompt"
          {File.read!(p), File.stat!(p).mtime, p}

        File.exists?(Path.join(path, "_index.prompt")) ->
          p = Path.join(path, "_index.prompt")
          {File.read!(p), File.stat!(p).mtime, p}

        true ->
          {nil, nil, nil}
      end
    else
      {nil, nil, nil}
    end
  end

  defp check_major_version(name, major, content, path_info, prompts_dir, name_str) do
    tokens = Lexer.tokenize(content)

    case Parser.parse(tokens) do
      {:ok, %{init: %{def: def_map}}} ->
        file_version = def_map[:version]
        file_major = major_from_version(file_version)

        if file_major == major do
          {content, mtime, full_path} = path_info
          {content, mtime, full_path}
        else
          find_archive_or_raise(name, major, prompts_dir, name_str)
        end

      _ ->
        if major == 1 do
          {content, mtime, full_path} = path_info
          {content, mtime, full_path}
        else
          raise "prompt_not_found: #{name} with major version #{major}"
        end
    end
  end

  defp find_archive_or_raise(name, major, prompts_dir, name_str) do
    name_parts = Path.split(name_str)

    archive_path =
      if length(name_parts) > 1 do
        dir = Path.dirname(name_str)
        base = Path.basename(name_str)
        Path.join([prompts_dir, dir, "archive", "#{base}_v#{major}.prompt"])
      else
        Path.join([prompts_dir, "archive", "#{name_str}_v#{major}.prompt"])
      end

    if File.exists?(archive_path) do
      {File.read!(archive_path), File.stat!(archive_path).mtime, archive_path}
    else
      raise "prompt_not_found: #{name} with major version #{major}"
    end
  end

  @doc false
  def cache_key_for_compile(:inline, params, content, annotated) do
    compile_params =
      params
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Enum.into(%{})

    params_hash = :erlang.phash2(compile_params)
    content_hash = :erlang.phash2(content)
    {"inline", params_hash, content_hash, annotated}
  end

  def cache_key_for_compile(prompt_key, params, content, annotated) do
    compile_params =
      params
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Enum.into(%{})

    content_hash = :erlang.phash2(content)
    params_hash = :erlang.phash2(compile_params)
    {to_string(prompt_key), params_hash, content_hash, annotated}
  end

  @doc false
  def count_tokens(text) do
    binary = if is_binary(text), do: text, else: IO.iodata_to_binary(text)
    words = binary |> String.trim() |> String.split()
    div(length(words) * 4, 3)
  end

  @doc false
  def strip_annotations(text) do
    text
    |> String.replace(~r/\[\[section:[^\]]+\]\]\n?/, "")
    |> String.replace(~r/\n?\[\[\/section\]\]/, "")
  end

  @doc false
  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc false
  def extract_response_contract(body) when is_list(body) do
    response_blocks = ResponseCollector.collect_response_blocks(body)

    case response_blocks do
      [] ->
        nil

      [{content, _line} | _] ->
        ResponseCollector.derive_schema(content)
    end
  end

  def extract_response_contract(_), do: nil

  @doc false
  def major_from_version(nil), do: 1
  def major_from_version(version) when is_integer(version), do: version

  def major_from_version(version) when is_binary(version) do
    version = String.replace(version, "v", "")

    case Integer.parse(version) do
      {major, "." <> _} -> major
      {major, _} -> major
      _ -> 1
    end
  end

  @doc false
  def indent_content(content, indent) when is_binary(content) do
    if indent == "" do
      content
    else
      content
      |> String.split("\n")
      |> Enum.map(fn
        "" -> ""
        "[[" <> _ = line -> line
        line -> [indent, line]
      end)
      |> Enum.intersperse("\n")
    end
  end

  def indent_content(content, indent) do
    indent_content(IO.iodata_to_binary(content), indent)
  end

  @doc false
  def validate_params_if_needed(_params, declarations) when declarations == %{}, do: :ok

  def validate_params_if_needed(params, declarations) do
    Validator.validate_params(params, declarations)
  end

  @doc false
  def apply_defaults(params, declarations) do
    declarations
    |> Enum.filter(fn {_name, spec} -> Map.has_key?(spec, :default) and spec.default != nil end)
    |> Enum.reduce(params, fn {name, spec}, acc ->
      clean_name = name |> String.trim_leading("@")
      clean_atom = safe_to_atom(clean_name)

      if Map.has_key?(acc, clean_atom) or Map.has_key?(acc, clean_name) do
        acc
      else
        Map.put(acc, clean_atom, spec.default)
      end
    end)
  end

  @doc false
  def extract_error_with_line(message, tokens) do
    if String.contains?(message, "line") or String.contains?(message, "at line") do
      message
    else
      last_token = List.last(tokens)

      if last_token && last_token.line do
        "#{message} (near line #{last_token.line})"
      else
        message
      end
    end
  end

  @doc false
  def add_line_info_to_validation_error(message, content) when is_binary(content) do
    if String.contains?(message, "line") do
      message
    else
      case Regex.run(
             ~r/(unknown_variable|missing_param|invalid_type|invalid_enum|out_of_range):\s*@?(\w+)/,
             message
           ) do
        [_, _type, var_name] ->
          case find_var_line_number(content, var_name) do
            nil -> message
            line_num -> "#{message} (at line #{line_num})"
          end

        _ ->
          message
      end
    end
  end

  defp find_var_line_number(content, var_name) do
    content
    |> String.split(["\r\n", "\n"], trim: false)
    |> Enum.with_index(1)
    |> Enum.reduce_while(nil, fn {line, line_num}, _acc ->
      if String.contains?(line, "@#{var_name}") do
        {:halt, line_num}
      else
        {:cont, nil}
      end
    end)
  end

  @doc false
  def ensure_atom(k) when is_atom(k), do: k

  def ensure_atom(k) when is_binary(k) do
    try do
      String.to_existing_atom(k)
    rescue
      ArgumentError -> k
    end
  end

  @doc false
  def get_param(params, key_str) do
    case Map.get(params, key_str) do
      nil ->
        Enum.find_value(params, fn
          {k, v} when is_atom(k) ->
            if Atom.to_string(k) == key_str, do: v

          _ ->
            nil
        end)

      value ->
        value
    end
  end

  @doc false
  def infer_type(v) when is_binary(v), do: "string"
  def infer_type(v) when is_integer(v), do: "number"
  def infer_type(v) when is_float(v), do: "number"
  def infer_type(v) when is_boolean(v), do: "boolean"
  def infer_type(v) when is_nil(v), do: "null"
  def infer_type(v) when is_list(v), do: "array"
  def infer_type(v) when is_map(v), do: "object"
  def infer_type(_), do: "unknown"

  @doc false
  def extract_init_vars(init) do
    vars =
      Enum.reduce(init.fragments, MapSet.new(), fn {_name, spec}, acc ->
        matches = Regex.scan(~r/@(\w+)/, spec.type || "") |> Enum.map(fn [_, v] -> v end)
        Enum.reduce(matches, acc, &MapSet.put(&2, &1))
      end)

    Enum.reduce(init.params, vars, fn {_name, spec}, acc ->
      if is_binary(spec.type) do
        matches = Regex.scan(~r/@(\w+)/, spec.type) |> Enum.map(fn [_, v] -> v end)
        Enum.reduce(matches, acc, &MapSet.put(&2, &1))
      else
        acc
      end
    end)
  end

  @doc false
  def type_matches?("string", "string"), do: true
  def type_matches?("string", "null"), do: true
  def type_matches?("number", "number"), do: true
  def type_matches?("boolean", "boolean"), do: true
  def type_matches?("null", "null"), do: true
  def type_matches?("array", "array"), do: true
  def type_matches?("object", "object"), do: true
  def type_matches?(_, _), do: false

  @doc false
  def extract_defaults_from_metadata(%{params: params}) when is_map(params) do
    params
    |> Enum.filter(fn {_name, spec} -> Map.has_key?(spec, :default) and spec.default != nil end)
    |> Enum.into(%{}, fn {name, spec} ->
      clean_atom = safe_to_atom(name)
      {clean_atom, spec.default}
    end)
  end

  def extract_defaults_from_metadata(_), do: %{}

  @doc false
  def validate_response(response, contract, strict) do
    errors =
      for {field, field_spec} <- contract, reduce: [] do
        acc ->
          required = Map.get(field_spec, :required, false)
          expected_type = Map.get(field_spec, :type, "string")

          field_errors =
            with :ok <- check_required_field(required, field, response),
                 :ok <- check_field_type(field, expected_type, response) do
              []
            else
              {:error, msg} -> [msg]
            end

          acc ++ field_errors
      end

    final_errors =
      if strict and Map.keys(response) -- Map.keys(contract) != [] do
        extra_fields = Map.keys(response) -- Map.keys(contract)
        errors ++ ["Unexpected fields: #{Enum.join(extra_fields, ", ")}"]
      else
        errors
      end

    case final_errors do
      [] -> :ok
      errors -> {:error, Enum.join(errors, "; ")}
    end
  end

  defp check_required_field(true, field, response) do
    if Map.has_key?(response, field), do: :ok, else: {:error, "Missing required field: #{field}"}
  end

  defp check_required_field(false, _field, _response), do: :ok

  defp check_field_type(_field, _expected_type, response) when response == %{}, do: :ok

  defp check_field_type(field, expected_type, response) do
    if Map.has_key?(response, field) do
      actual_value = Map.get(response, field)
      actual_type = infer_type(actual_value)

      if type_matches?(expected_type, actual_type) do
        :ok
      else
        {:error, "Field #{field} has type #{actual_type}, expected #{expected_type}"}
      end
    else
      :ok
    end
  end

  defp safe_to_atom(binary) when is_binary(binary) do
    String.to_existing_atom(binary)
  rescue
    ArgumentError -> binary
  end

  defp safe_to_atom(_), do: nil
end
