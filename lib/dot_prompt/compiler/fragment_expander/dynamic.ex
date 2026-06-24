defmodule DotPrompt.Compiler.FragmentExpander.Dynamic do
  @moduledoc """
  Expands dynamic fragments {{}}. These interpolate runtime variables from params.
  Dynamic fragments are NOT cached - they're evaluated fresh each request.
  """

  @spec expand(String.t(), map()) :: {:ok, String.t(), MapSet.t(), map()} | {:error, String.t()}
  def expand(fragment_path, params) do
    var_name = String.trim(fragment_path, "{") |> String.trim("}")
    used = MapSet.new([var_name])

    # Try string key first (from JSON/API), then atom key (Elixir maps)
    value =
      case Map.fetch(params, var_name) do
        {:ok, v} ->
          v

        :error ->
          try do
            case Map.fetch(params, String.to_existing_atom(var_name)) do
              {:ok, v} -> v
              :error -> nil
            end
          rescue
            ArgumentError -> nil
          end
      end

    case value do
      nil ->
        {:error, "dynamic_fragment_variable_not_found: #{var_name}"}

      v when is_list(v) ->
        {:ok, Enum.join(v, ", "), used, %{}}

      v ->
        {:ok, to_string(v), used, %{}}
    end
  end
end
