defmodule DotPrompt do
  @moduledoc """
  Main API for dot-prompt.
  """
  require Logger

  alias DotPrompt.Compiler.VaryCompositor
  alias DotPrompt.Injector
  alias DotPrompt.Telemetry
  alias DotPrompt.Compiler
  alias DotPrompt.Helpers
  alias DotPrompt.Cache.{Fragment, Structural, Vary}

  @type prompt_name :: String.t()
  @type params :: map()
  @type runtime :: map()
  @type compile_opts :: [
          indent: integer(),
          seed: integer()
        ]

  @type schema_info :: %{
          name: prompt_name(),
          version: integer(),
          description: String.t() | nil,
          mode: String.t() | nil,
          docs: String.t() | nil,
          params: map(),
          fragments: map()
        }

  @doc "Lists all available prompts including fragments."
  @spec list_prompts(keyword()) :: [prompt_name()]
  def list_prompts(opts \\ []) do
    path = Helpers.prompts_dir(opts)

    if File.exists?(path) do
      "#{path}/**/*.prompt"
      |> Path.wildcard()
      |> Enum.map(fn full_path ->
        full_path
        |> Path.relative_to(path)
        |> String.replace_suffix(".prompt", "")
      end)
      |> Enum.sort()
    else
      []
    end
  end

  @doc "Lists only root-level prompts (excluding fragments)."
  @spec list_root_prompts() :: [prompt_name()]
  def list_root_prompts do
    list_prompts()
    |> Enum.reject(&String.contains?(&1, "/"))
  end

  @doc "Lists only fragment prompts."
  @spec list_fragment_prompts() :: [prompt_name()]
  def list_fragment_prompts do
    list_prompts()
    |> Enum.filter(&String.contains?(&1, "/"))
    |> Enum.sort()
  end

  def list_collections(opts \\ []) do
    path = Helpers.prompts_dir(opts)

    if File.exists?(path) do
      File.ls!(path)
      |> Enum.filter(&File.dir?(Path.join(path, &1)))
      |> Enum.reject(&String.starts_with?(&1, "_"))
    else
      []
    end
  end

  @doc "Extracts the schema and metadata for a given prompt."
  @spec schema(prompt_name(), integer() | nil, keyword()) ::
          {:ok, schema_info()} | {:error, map()}
  def schema(prompt_name, major \\ nil, opts \\ []) do
    prompts_dir = Helpers.prompts_dir(opts)

    {mtime, _path_for_cache} =
      if is_binary(prompt_name) and !String.contains?(prompt_name, "\n") and
           !String.contains?(prompt_name, " ") do
        p = Path.join(prompts_dir, prompt_name <> ".prompt")
        {if(File.exists?(p), do: File.stat!(p).mtime, else: 0), p}
      else
        {0, nil}
      end

    case Fragment.get({:schema, to_string(prompt_name), major, mtime}) do
      {:ok, result} ->
        {:ok, result}

      _ ->
        try do
          {_content, actual_mtime, path} =
            Helpers.load_prompt_file_with_meta(prompt_name, major, "", opts)

          Compiler.do_parse_schema(prompt_name, path, actual_mtime, major)
        rescue
          _ ->
            {:error,
             %{
               error: "prompt_not_found",
               message: "Could not find prompt #{prompt_name} (major: #{major || "latest"})"
             }}
        end
    end
  end

  @doc """
  Compiles a prompt for given params.
  Returns {:ok, %DotPrompt.Result{}} or {:error, map()}
  """
  @spec compile(prompt_name() | String.t(), params(), compile_opts()) ::
          {:ok, DotPrompt.Result.t()} | {:error, map()}
  def compile(prompt_name_or_content, params, opts \\ []) do
    case compile_to_iodata(prompt_name_or_content, params, opts) do
      {:ok, skeleton_iodata, final_selections, used_vars, cached_files_meta, hit, warnings,
       response_contract, major, version, declarations} ->
        skeleton = IO.iodata_to_binary(skeleton_iodata)

        clean_params =
          Enum.into(declarations, %{}, fn {k, v} ->
            if k in ["@version", "@major"] do
              {k, v}
            else
              {String.trim_leading(k, "@"), v}
            end
          end)

        result = %DotPrompt.Result{
          prompt: skeleton,
          response_contract: response_contract,
          vary_selections: final_selections,
          compiled_tokens: Helpers.count_tokens(skeleton),
          cache_hit: hit,
          major: major,
          version: version,
          metadata: %{
            used_vars: used_vars,
            files: cached_files_meta,
            warnings: warnings,
            params: clean_params
          }
        }

        Logger.debug("DotPrompt.compile used_vars: #{inspect(used_vars)}")

        {:ok, result}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Internal compile that returns iodata for maximum efficiency when nesting fragments.
  """
  @spec compile_to_iodata(prompt_name() | String.t(), params(), compile_opts()) ::
          {:ok, iodata(), map(), MapSet.t(), map(), boolean(), [String.t()], map() | nil,
           integer(), integer() | String.t(), map()}
          | {:error, map()}
  def compile_to_iodata(prompt_name_or_content, params, opts \\ []) do
    annotated = Keyword.get(opts, :annotated, false)
    current_dir = Keyword.get(opts, :current_dir, "")
    requested_major = Keyword.get(opts, :major)
    start_time = System.monotonic_time()

    params = Enum.into(params, %{}, fn {k, v} -> {Helpers.ensure_atom(k), v} end)

    Telemetry.start_render(to_string(prompt_name_or_content), params)

    content_ref =
      if String.contains?(prompt_name_or_content, "\n") or
           String.contains?(prompt_name_or_content, " ") or
           String.contains?(prompt_name_or_content, "{{") do
        {:inline, prompt_name_or_content}
      else
        {:file, to_string(prompt_name_or_content)}
      end

    prompt_key =
      case content_ref do
        {:inline, _} -> :inline
        {:file, name} -> name
      end

    new_current_dir =
      if prompt_key != :inline do
        case Path.dirname(prompt_key) do
          "." -> current_dir
          dir -> if current_dir == "", do: dir, else: Path.join(current_dir, dir)
        end
      else
        current_dir
      end

    {content, files_meta} =
      case content_ref do
        {:inline, c} ->
          {c, %{}}

        {:file, name} ->
          {c, t, p} = Helpers.load_prompt_file_with_meta(name, requested_major, current_dir, opts)
          {c, %{p => t}}
      end

    cache_key = Helpers.cache_key_for_compile(prompt_key, params, content, annotated)

    case Structural.get(cache_key) do
      {:ok,
       {skeleton_iodata, vary_map, used_vars, cached_files_meta, major, version, declarations}} ->
        if Compiler.stale?(cached_files_meta) do
          Compiler.compile_fresh_with_content(
            prompt_name_or_content,
            content,
            files_meta,
            params,
            opts,
            start_time,
            cache_key,
            new_current_dir
          )
        else
          duration = System.monotonic_time() - start_time

          skeleton_binary = IO.iodata_to_binary(skeleton_iodata)

          {output_skeleton, final_selections} =
            if annotated do
              {_resolved, selections} =
                VaryCompositor.resolve_full(skeleton_binary, vary_map, opts[:seed], params)

              {skeleton_iodata, selections}
            else
              {resolved, selections} =
                VaryCompositor.resolve_full(skeleton_binary, vary_map, opts[:seed], params)

              {Helpers.strip_annotations(resolved), selections}
            end

          compiled_tokens = Helpers.count_tokens(output_skeleton)

          Telemetry.stop_render(
            to_string(prompt_name_or_content),
            params,
            System.convert_time_unit(duration, :native, :millisecond),
            %{
              compiled_tokens: compiled_tokens,
              vary_selections: final_selections,
              cache_hit: true
            }
          )

          response_contract =
            case Structural.get({:contract, cache_key}) do
              {:ok, contract} -> contract
              _ -> nil
            end

          {:ok, output_skeleton, final_selections, used_vars, cached_files_meta, true, [],
           response_contract, major, version, declarations}
        end

      {:ok, {_skeleton_iodata, _vary_map, _used_vars, _cached_files_meta, _major, _version}} ->
        Compiler.compile_fresh_with_content(
          prompt_name_or_content,
          content,
          files_meta,
          params,
          opts,
          start_time,
          cache_key,
          new_current_dir
        )

      _ ->
        Compiler.compile_fresh_with_content(
          prompt_name_or_content,
          content,
          files_meta,
          params,
          opts,
          start_time,
          cache_key,
          new_current_dir
        )
    end
  end

  def inject(template, runtime) do
    Injector.inject(template, runtime)
  end

  @doc """
  Renders a prompt by compiling it and injecting runtime data.
  """
  @spec render(prompt_name() | String.t(), params(), runtime(), compile_opts()) ::
          {:ok, DotPrompt.Result.t()} | {:error, map()}
  def render(prompt_name_or_content, params, runtime, opts \\ []) do
    params = Enum.into(params, %{}, fn {k, v} -> {Helpers.ensure_atom(k), v} end)
    runtime = Enum.into(runtime, %{}, fn {k, v} -> {Helpers.ensure_atom(k), v} end)

    case compile(prompt_name_or_content, params, opts) do
      {:ok, %DotPrompt.Result{} = compile_result} ->
        defaults = Helpers.extract_defaults_from_metadata(compile_result.metadata)
        all_values = Map.merge(defaults, Map.merge(params, runtime))
        result_prompt = inject(compile_result.prompt, all_values)
        injected_tokens = Helpers.count_tokens(result_prompt)

        final_result = %{
          compile_result
          | prompt: result_prompt,
            injected_tokens: injected_tokens
        }

        {:ok, final_result}

      {:error, _} = error ->
        error
    end
  end

  def compile_string(content, params, opts \\ []) do
    compile(content, params, opts)
  end

  @doc """
  Invalidates the cache for a specific prompt.
  """
  @spec invalidate_cache(prompt_name()) :: :ok
  def invalidate_cache(prompt_name) do
    Structural.invalidate_name(prompt_name)
    Vary.invalidate_prompt(prompt_name)
    :ok
  end

  @doc """
  Invalidates all caches (structural, fragment, and vary).
  """
  @spec invalidate_all_cache() :: :ok
  def invalidate_all_cache do
    Structural.clear()
    Fragment.clear()
    Vary.clear()
    :ok
  end

  @doc """
  Returns statistics about the current cache usage.
  """
  @spec cache_stats() :: %{structural: integer(), fragment: integer(), vary: integer()}
  def cache_stats do
    %{
      structural: Structural.count(),
      fragment: Fragment.count(),
      vary: Vary.count()
    }
  end

  @doc """
  Validates an LLM response against a response contract.
  """
  @spec validate_output(String.t(), map(), keyword()) :: :ok | {:error, String.t()}
  def validate_output(response_json, contract, opts \\ []) do
    strict = Keyword.get(opts, :strict, true)

    case Jason.decode(response_json) do
      {:ok, response} when is_map(response) ->
        Helpers.validate_response(response, contract, strict)

      {:ok, _} ->
        {:error, "Response must be a JSON object"}

      {:error, reason} ->
        {:error, "Invalid JSON: #{inspect(reason)}"}
    end
  end
end
