defmodule DotPrompt.Injector do
  @moduledoc """
  Fills runtime variable placeholders using an efficient single-pass injection strategy.
  """

  # Matches {{key}}, @{{key}}, or @key\b
  @injection_regex ~r/@?\{\{([\w\d_]+)\}\}|@([\w\d_]+)\b/

  @doc """
  Injects runtime parameters into the template string.
  """
  def inject(template, runtime_params) do
    # Convert all keys to strings once for fast lookup
    params_map =
      Enum.into(runtime_params, %{}, fn {k, v} ->
        {to_string(k), to_string(v)}
      end)

    Regex.replace(@injection_regex, template, fn full, group1, group2 ->
      # group1 is from {{key}} or @{{key}}, group2 is from @key
      key = if group1 != "", do: group1, else: group2

      case Map.fetch(params_map, key) do
        {:ok, value} -> value
        :error -> full
      end
    end)
  end
end
