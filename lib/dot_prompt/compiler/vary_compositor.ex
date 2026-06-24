defmodule DotPrompt.Compiler.VaryCompositor do
  @moduledoc """
  Resolves vary slots after structural compilation using an efficient single-pass approach.
  """

  @vary_regex ~r/\[\[vary:"([^"]+)"\]\]/

  # Pre-register atoms used for param lookups to avoid "not an existing atom" errors
  # These atoms are used when looking up params with atom keys
  @preloaded_atoms [:intro, :intro_style, :style]

  # Ensure atoms are loaded at compile time by referencing them
  defp ensure_atoms_loaded, do: @preloaded_atoms

  @doc """
  Resolves vary slots and returns the final string.
  """
  def resolve(skeleton, vary_map, seed \\ nil, params \\ %{}) do
    {result, _selections} = resolve_full(skeleton, vary_map, seed, params)
    result
  end

  @doc """
  Resolves vary slots and returns both the string and the selections made.
  """
  def resolve_full(skeleton, vary_map, seed \\ nil, params \\ %{}) do
    # Ensure preloaded atoms are registered
    ensure_atoms_loaded()
    selections = pre_calculate_selections(vary_map, seed, params)

    # Single-pass resolution using Regex.replace with a function
    result =
      Regex.replace(@vary_regex, skeleton, fn _full, name ->
        case Map.get(selections, name) do
          {_id, text} -> text
          nil -> "[[MISSING VARY: #{name}]]"
        end
      end)

    # Return final text and a map of {id, text} for each slot
    rich_selections =
      Enum.into(selections, %{}, fn {name, {id, text}} ->
        {name, %{id: id, text: text}}
      end)

    {result, rich_selections}
  end

  defp pre_calculate_selections(vary_map, seed, params) do
    Enum.into(vary_map, %{}, fn {name, branches} ->
      clean_name = String.trim_leading(to_string(name), "@")
      atom_name = to_existing_or_nil(clean_name)

      selection =
        cond do
          # Param match
          # Try multiple key formats for maximum compatibility (@name string, name string, name atom)
          (val =
             Map.get(params, name) ||
               Map.get(params, clean_name) ||
               (atom_name && Map.get(params, atom_name))) !=
              nil ->
            target = to_string(val)
            match = Enum.find(branches, fn {id, _, _} -> to_string(id) == target end)
            if match, do: match_to_selection(match), else: select_branch(branches, seed)

          # Seeded selection
          seed != nil ->
            select_branch(branches, seed)

          # Random fallback
          true ->
            select_branch(branches, nil)
        end

      {to_string(name), selection}
    end)
  end

  defp match_to_selection({id, _label, text}), do: {id, maybe_render_tokens(text)}

  defp to_existing_or_nil(s) do
    try do
      String.to_existing_atom(s)
    rescue
      ArgumentError -> nil
    end
  end

  defp select_branch(branches, seed) when is_integer(seed) do
    # Stable ordering and hashing for deterministic selection
    branch_ids = Enum.map_join(branches, ",", fn {id, _, _} -> inspect(id) end)
    hash_input = "#{seed}:#{branch_ids}"
    <<int_val::64, _::binary>> = :crypto.hash(:sha256, hash_input)

    {id, _label, text} = Enum.at(branches, rem(int_val, length(branches)))
    {id, maybe_render_tokens(text)}
  end

  defp select_branch(branches, _nil_seed) do
    {id, _label, text} = Enum.random(branches)
    {id, maybe_render_tokens(text)}
  end

  defp maybe_render_tokens(text) when is_binary(text), do: text

  defp maybe_render_tokens(tokens) when is_list(tokens) do
    # Using iodata for efficient string construction
    tokens
    |> Enum.map(fn
      {:text, content} -> content
      {:var, name} -> "{{#{name}}}"
      {:param, name} -> "@{#{name}}"
    end)
    |> IO.iodata_to_binary()
  end
end
