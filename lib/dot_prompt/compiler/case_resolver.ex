defmodule DotPrompt.Compiler.CaseResolver do
  @moduledoc """
  Resolves case blocks by matching variables against branches.
  """

  @doc """
  Resolves a case block based on the provided variable value.
  """
  def resolve(var_value, branches) do
    val_str = normalize_value(var_value)

    case Enum.find(branches, &match_branch?(&1, val_str, var_value)) do
      {_id, _label, nodes} ->
        nodes || []

      {:if, _var, cond, then_nodes, elifs, else_node} ->
        # Nested if logic within a case branch
        if resolve_condition(cond, var_value) do
          then_nodes
        else
          resolve_elifs(elifs, else_node, var_value)
        end

      nil ->
        []
    end
  end

  defp normalize_value(nil), do: "nil"
  defp normalize_value(v), do: to_string(v)

  defp match_branch?({id, _label, _nodes}, val_str, _), do: to_string(id) == val_str
  defp match_branch?({:if, var, _, _, _, _}, val_str, _), do: to_string(var) == val_str
  defp match_branch?(_, _, _), do: false

  defp resolve_condition(cond_str, var_value) when is_binary(cond_str) do
    cond_str = String.trim(cond_str)

    case String.downcase(cond_str) do
      "is true" -> var_value == true
      "is false" -> var_value == false
      "is nil" -> var_value == nil
      "equals " <> rest -> to_string(var_value) == String.trim(rest)
      "equal " <> rest -> to_string(var_value) == String.trim(rest)
      _ -> false
    end
  end

  defp resolve_condition(_, _), do: false

  defp resolve_elifs(elifs, else_node, var_value) do
    Enum.find_value(elifs, else_node || [], fn {c, nodes} ->
      if resolve_condition(c, var_value), do: nodes
    end)
  end
end
