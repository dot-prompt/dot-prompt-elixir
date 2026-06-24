defmodule DotPrompt.Compiler do
  @moduledoc """
  Compiles DotPrompt (.prompt) template files into rendered output.

  ## Purpose

  The Compiler is the core of the DotPrompt system. It takes a `.prompt` file
  path or raw content, tokenizes it via `DotPrompt.Parser.Lexer`, parses it
  into an AST, validates the structure, and compiles the AST into rendered
  prompt text with interpolated parameters.

  ## Key Functions

  - `do_parse_schema/5` — Parses a prompt file and returns its schema (params,
    fragments, docs, response contract) without rendering
  - `compile_fresh_with_content/8` — Full compile pipeline: tokenize, parse,
    validate, compile, and resolve vary blocks
  - `compile_ast/2` — Recursively compiles AST nodes (text, if, case, vary,
    fragments) into rendered output
  - `stale?/1` — Checks if cached compiled output is stale by comparing file
    mtimes

  ## Compilation Pipeline

  1. Tokenize → parse → validate (structural validation)
  2. Apply parameter defaults
  3. Validate params against declarations
  4. Resolve response contracts across blocks
  5. Compile AST with `@param` interpolation
  6. Resolve `{vary}` blocks (at-runtime variation)
  7. Cache parsed schema and compiled structural output
  """

  require Logger

  alias DotPrompt.Parser.{Lexer, Parser, Validator}
  alias DotPrompt.Compiler.{VaryCompositor, ResponseCollector, Context}
  alias DotPrompt.Cache.{Structural, Fragment}
  alias DotPrompt.Telemetry
  alias DotPrompt.Helpers
  alias DotPrompt.AST

  @doc false
  def do_parse_schema(prompt_name, path, mtime, major) do
    try do
      content = File.read!(path)
      tokens = Lexer.tokenize(content)

      case Parser.parse(tokens) do
        {:error, message} ->
          {:error, %{error: "syntax_error", message: message}}

        {:ok, ast} ->
          params = Validator.parse_param_declarations_for_schema(ast.init)
          def_block = Validator.parse_def_block(ast.init)
          docs = Validator.parse_docs_block(ast.init)
          fragments = Validator.parse_fragment_declarations(ast.init)

          vary_vars = AST.extract_vary_vars(ast.body)

          schema_params =
            Enum.into(params, %{}, fn {name, spec} ->
              clean_name = name |> to_string() |> String.trim_leading("@")

              spec_map =
                %{type: spec.type, lifecycle: spec.lifecycle, doc: spec.doc}
                |> Helpers.maybe_put(:default, spec[:default])
                |> Helpers.maybe_put(:values, spec[:values])
                |> Helpers.maybe_put(:range, spec[:range])
                |> Map.put(:vary, MapSet.member?(vary_vars, clean_name))

              {clean_name, spec_map}
            end)

          schema_fragments =
            Enum.into(fragments, %{}, fn {name, spec} ->
              clean_name =
                name
                |> to_string()
                |> String.trim_leading("{")
                |> String.trim_trailing("}")

              spec_map =
                %{type: spec.type, doc: spec.doc}
                |> Helpers.maybe_put(:from, spec[:from])

              {clean_name, spec_map}
            end)

          response_contract = Helpers.extract_response_contract(ast.body)

          result =
            Map.merge(def_block, %{
              name: to_string(prompt_name),
              major: Helpers.major_from_version(def_block[:version]),
              version: def_block[:version] || 1,
              params: schema_params,
              fragments: schema_fragments,
              docs: docs,
              response_contract: response_contract
            })

          Logger.debug(
            "DotPrompt.Compiler.do_parse_schema params for #{prompt_name}: #{inspect(schema_params)}"
          )

          Fragment.put({:schema, to_string(prompt_name), major, mtime}, result)
          {:ok, result}
      end
    rescue
      e ->
        {:error, %{error: "parsing_failed", message: inspect(e)}}
    end
  end

  @doc false
  def compile_fresh_with_content(
        prompt_name_or_content,
        content,
        files_meta,
        params,
        opts,
        start_time,
        cache_key,
        current_dir
      ) do
    annotated = Keyword.get(opts, :annotated, false)
    tokens = Lexer.tokenize(content)

    case Parser.parse(tokens) do
      {:error, message} ->
        handle_parsing_error(prompt_name_or_content, params, start_time, message, tokens)

      {:ok, ast} ->
        case Validator.validate(ast) do
          {:ok, warnings} ->
            process_valid_ast(
              prompt_name_or_content,
              content,
              files_meta,
              params,
              opts,
              start_time,
              cache_key,
              annotated,
              ast,
              warnings,
              current_dir
            )

          {:error, reason} ->
            handle_validation_error(prompt_name_or_content, params, start_time, reason, content)
        end
    end
  end

  defp handle_parsing_error(prompt_name, params, start_time, message, tokens) do
    error_msg = Helpers.extract_error_with_line(message, tokens)
    Logger.error("dot-prompt compilation error: #{error_msg}")

    Telemetry.stop_render(
      to_string(prompt_name),
      params,
      System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond),
      %{compiled_tokens: 0}
    )

    {:error, %{error: "syntax_error", message: error_msg}}
  end

  defp handle_validation_error(prompt_name, params, start_time, reason, content) do
    reason_with_line = Helpers.add_line_info_to_validation_error(reason, content)
    Logger.error("dot-prompt validation error: #{reason_with_line}")

    Telemetry.stop_render(
      to_string(prompt_name),
      params,
      System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond),
      %{compiled_tokens: 0}
    )

    {:error, %{error: "validation_error", message: reason_with_line}}
  end

  defp process_valid_ast(
         prompt_name_or_content,
         content,
         files_meta,
         params,
         opts,
         start_time,
         cache_key,
         annotated,
         ast,
         warnings,
         current_dir
       ) do
    init = ast.init || %{params: %{}, fragments: %{}, docs: nil}
    declarations = Validator.parse_param_declarations_for_schema(init)
    params_with_defaults = Helpers.apply_defaults(params, declarations)

    case Helpers.validate_params_if_needed(params_with_defaults, declarations) do
      :ok ->
        fragment_defs = Validator.parse_fragment_declarations(init)

        case handle_response_contracts(ast.body, warnings) do
          {:error, msg} ->
            {:error, %{error: "validation_error", message: msg}}

          {:ok, warnings, first_schema} ->
            init_vars = Helpers.extract_init_vars(init)

            context =
              Context.new(params_with_defaults, fragment_defs, declarations, opts)
              |> Map.put(:files_meta, files_meta)
              |> Map.put(:current_dir, current_dir)
              |> Map.update!(:used_vars, &MapSet.union(&1, init_vars))

            compile_and_build_result(
              prompt_name_or_content,
              content,
              params,
              start_time,
              cache_key,
              annotated,
              ast,
              warnings,
              first_schema,
              context
            )
        end

      {:error, reason} ->
        handle_validation_error(
          prompt_name_or_content,
          params,
          start_time,
          reason,
          content
        )
    end
  end

  defp handle_response_contracts(body, warnings) do
    response_blocks = ResponseCollector.collect_response_blocks(body)

    schemas =
      Enum.map(response_blocks, fn {content, _line} ->
        ResponseCollector.derive_schema(content)
      end)

    comparison = ResponseCollector.compare_schemas(schemas)

    case comparison do
      :incompatible ->
        {:error, "incompatible_contracts: response blocks have incompatible schemas"}

      _ ->
        first_schema = Enum.at(schemas, 0)

        maybe_warn =
          if comparison == :compatible,
            do: ["compatible_contracts: response blocks have same fields but different values"],
            else: []

        {:ok, warnings ++ maybe_warn, first_schema}
    end
  end

  defp compile_and_build_result(
         prompt_name_or_content,
         content,
         params,
         start_time,
         cache_key,
         annotated,
         ast,
         warnings,
         first_schema,
         context
       ) do
    case compile_ast(ast.body, context) do
      {:error, reason} ->
        reason_with_line = Helpers.add_line_info_to_validation_error(reason, content)
        Logger.error("dot-prompt compilation error: #{reason_with_line}")

        Telemetry.stop_render(
          to_string(prompt_name_or_content),
          params,
          System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond),
          %{compiled_tokens: 0}
        )

        {:error, %{error: "validation_error", message: reason_with_line}}

      {skeleton_iodata, vary_map, used_vars, total_files_meta, _count} ->
        seed = context.opts[:seed]
        params_with_defaults = context.params
        declarations = context.declarations
        def_info = Validator.parse_def_block(ast.init)
        version = def_info[:version] || 1
        major = Helpers.major_from_version(version)

        skeleton_binary = IO.iodata_to_binary(skeleton_iodata)

        skeleton_binary =
          if first_schema do
            schema_json = Jason.encode!(first_schema, pretty: true)
            String.replace(skeleton_binary, "{response_contract}", schema_json)
          else
            skeleton_binary
          end

        {output_skeleton, vary_selections} =
          resolve_and_strip(skeleton_binary, vary_map, seed, params_with_defaults, annotated)

        Structural.put(
          cache_key,
          {skeleton_iodata, vary_map, used_vars, total_files_meta, major, version, declarations}
        )

        if first_schema do
          Structural.put({:contract, cache_key}, first_schema)
        end

        duration = System.monotonic_time() - start_time
        compiled_tokens = Helpers.count_tokens(output_skeleton)

        Telemetry.stop_render(
          to_string(prompt_name_or_content),
          params,
          System.convert_time_unit(duration, :native, :millisecond),
          %{
            compiled_tokens: compiled_tokens,
            vary_selections: vary_selections,
            cache_hit: false
          }
        )

        {:ok, output_skeleton, vary_selections, used_vars, total_files_meta, false, warnings,
         first_schema, major, version, declarations}
    end
  end

  defp resolve_and_strip(skeleton_binary, vary_map, seed, params, true) do
    {_resolved, selections} =
      VaryCompositor.resolve_full(skeleton_binary, vary_map, seed, params)

    {skeleton_binary, selections}
  end

  defp resolve_and_strip(skeleton_binary, vary_map, seed, params, false) do
    {resolved, selections} =
      VaryCompositor.resolve_full(skeleton_binary, vary_map, seed, params)

    {Helpers.strip_annotations(resolved), selections}
  end

  @doc false
  def stale?(files_meta) when is_map(files_meta) do
    Enum.any?(files_meta, fn {path, cached_mtime} ->
      case File.stat(path) do
        {:ok, %{mtime: disk_mtime}} -> disk_mtime > cached_mtime
        _ -> true
      end
    end)
  end

  def stale?(_), do: true

  @doc false
  def compile_ast(nodes, context) do
    indent = String.duplicate("  ", context.indent_level)

    Enum.reduce_while(
      nodes,
      {[], context.vary_map, context.used_vars, context.files_meta, context.section_count},
      fn node, acc ->
        case node do
          {:text, t} ->
            AST.handle_text_node(t, indent, context, acc)

          {:if, var, cond, then_nodes, elifs, else_node} ->
            AST.handle_if_node(var, cond, then_nodes, elifs, else_node, context, acc)

          {:case, var, branches} ->
            AST.handle_case_node(var, branches, context, acc)

          {:vary, name, branches} ->
            AST.handle_vary_node(name, branches, context, acc)

          {:fragment_static, path} ->
            AST.handle_static_fragment(path, context, acc)

          {:fragment_dynamic, path} ->
            AST.handle_dynamic_fragment(path, context, acc)

          _ ->
            {:cont, acc}
        end
      end
    )
    |> wrap_result()
  end

  defp wrap_result({:error, _} = err), do: err
  defp wrap_result({text, v, vars, f, c}), do: {text, v, vars, f, c}
end
