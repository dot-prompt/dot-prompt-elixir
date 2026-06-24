defmodule DotPrompt.Compiler.ResponseCollector do
  @moduledoc """
  Collects response blocks from AST and derives schema.
  """

  @doc """
  Collects all response blocks from the AST body.
  Returns a list of {content, line} tuples.
  """
  def collect_response_blocks(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, &do_collect/1)
  end

  defp do_collect({:response, content, line}), do: [{content, line}]

  defp do_collect({:if, _var, _cond, then_nodes, elifs, else_node}) do
    then_results = collect_response_blocks(then_nodes)
    elif_results = Enum.flat_map(elifs, fn {_c, nodes} -> collect_response_blocks(nodes) end)
    else_results = if else_node, do: collect_response_blocks(else_node), else: []
    then_results ++ elif_results ++ else_results
  end

  defp do_collect({:case, _var, branches}) do
    Enum.flat_map(branches, fn
      {_id, _label, nodes} -> collect_response_blocks(nodes)
      _ -> []
    end)
  end

  defp do_collect({:vary, _var, branches}) do
    Enum.flat_map(branches, fn
      {_id, _label, nodes} -> collect_response_blocks(nodes)
      _ -> []
    end)
  end

  defp do_collect(_), do: []

  @doc """
  Derives a schema map from a JSON string.
  Returns a full JSON schema object.
  """
  def derive_schema(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, json} ->
        %{
          "type" => "object",
          "properties" => derive_schema_from_map(json)
        }

      {:error, _} ->
        %{}
    end
  end

  defp derive_schema_from_map(json) when is_map(json) do
    Enum.into(json, %{}, fn {k, v} ->
      {k, schema_for_value(v)}
    end)
  end

  defp schema_for_value(v) when is_binary(v) do
    case v do
      "string" -> %{"type" => "string", "required" => true}
      "number" -> %{"type" => "number", "required" => true}
      "integer" -> %{"type" => "integer", "required" => true}
      "boolean" -> %{"type" => "boolean", "required" => true}
      "array" -> %{"type" => "array", "required" => true}
      "object" -> %{"type" => "object", "required" => true}
      _ -> %{"type" => "string", "required" => true}
    end
  end

  defp schema_for_value(v) when is_integer(v), do: %{"type" => "integer", "required" => true}
  defp schema_for_value(v) when is_float(v), do: %{"type" => "number", "required" => true}
  defp schema_for_value(v) when is_boolean(v), do: %{"type" => "boolean", "required" => true}
  defp schema_for_value(v) when is_nil(v), do: %{"type" => "null", "required" => false}

  defp schema_for_value(v) when is_list(v) do
    if Enum.empty?(v) do
      %{"type" => "array", "required" => true, "items" => %{}}
    else
      first_item = Enum.at(v, 0)
      %{"type" => "array", "required" => true, "items" => schema_for_value(first_item)}
    end
  end

  defp schema_for_value(v) when is_map(v) do
    %{"type" => "object", "required" => true, "properties" => derive_schema_from_map(v)}
  end

  @doc """
  Compares multiple response schemas.
  Also identifies if they are chemically identical (same JSON source)
  or functionally identical (same structural schema but different source).
  """
  def compare_schemas([]), do: :identical
  def compare_schemas([_]), do: :identical

  def compare_schemas(schemas) do
    # Sort and clean schemas for structural comparison
    schemas_list = Enum.map(schemas, &sort_schema_map/1)

    [first | rest] = schemas_list

    # 1. Check structural compatibility
    status =
      if Enum.all?(rest, fn s -> s == first end) do
        :identical
      else
        case compare_schemas_rec(first, rest) do
          :compatible -> :compatible
          _ -> :incompatible
        end
      end

    status
  end

  defp compare_schemas_rec(_first, []) do
    :compatible
  end

  defp compare_schemas_rec(first, [next | rest]) do
    case schemas_compatible?(first, next) do
      true -> compare_schemas_rec(first, rest)
      false -> :incompatible
    end
  end

  defp schemas_compatible?(schema1, schema2) do
    type1 = schema1["type"] || schema1[:type]
    type2 = schema2["type"] || schema2[:type]

    if type1 != type2 do
      false
    else
      compare_schemas_by_type(type1, schema1, schema2)
    end
  end

  defp compare_schemas_by_type("object", schema1, schema2) do
    props1 = schema1["properties"] || schema1[:properties] || %{}
    props2 = schema2["properties"] || schema2[:properties] || %{}

    keys1 = Map.keys(props1) |> MapSet.new()
    keys2 = Map.keys(props2) |> MapSet.new()

    if keys1 == keys2 do
      Enum.all?(Map.keys(props1), fn k ->
        schemas_compatible?(props1[k], props2[k])
      end)
    else
      false
    end
  end

  defp compare_schemas_by_type("array", schema1, schema2) do
    items1 = schema1["items"] || schema1[:items] || %{}
    items2 = schema2["items"] || schema2[:items] || %{}
    schemas_compatible?(items1, items2)
  end

  defp compare_schemas_by_type(nil, schema1, schema2) do
    keys1 = Map.keys(schema1) |> MapSet.new()
    keys2 = Map.keys(schema2) |> MapSet.new()

    keys1 == keys2 &&
      Enum.all?(Map.keys(schema1), fn k -> schemas_compatible?(schema1[k], schema2[k]) end)
  end

  defp compare_schemas_by_type(_type, _schema1, _schema2) do
    true
  end

  defp sort_schema_map(schema) do
    schema
    |> Enum.into([], fn {k, v} -> {k, v} end)
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.into(%{}, fn {k, v} -> {k, sort_schema_value(v)} end)
  end

  defp sort_schema_value(%{"type" => "object", "properties" => props} = v) do
    Map.put(v, "properties", sort_schema_map(props))
  end

  defp sort_schema_value(%{"type" => "array", "items" => items} = v) do
    Map.put(v, "items", sort_schema_value(items))
  end

  defp sort_schema_value(v), do: v
end
