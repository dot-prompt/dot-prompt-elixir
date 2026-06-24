defmodule DotPrompt.Cache.Structural do
  @moduledoc """
  ETS-based cache for structural skeleton with precise invalidation support.
  """
  use GenServer

  @table :dot_prompt_structural_cache

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    :ets.new(@table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: :auto
    ])

    {:ok, %{}}
  end

  def init do
    :ets.new(@table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: :auto
    ])
  end

  @doc """
  Gets cached skeleton and metadata for the given key.
  """
  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> {:ok, value}
      [] -> :error
    end
  end

  @doc """
  Stores a value in the cache.
  """
  def put(key, value) do
    :ets.insert(@table, {key, value})
  end

  @doc """
  Selectively invalidates all entries matching the given prompt name.
  """
  def invalidate_name(name) do
    # Only delete keys for this specific prompt
    # Key format: {prompt_name, params_hash} or {"inline", params_hash, content_hash}
    :ets.match_delete(@table, {{to_string(name), :_}, :_})
    :ok
  end

  @doc """
  Clears all cached objects.
  """
  def clear do
    :ets.delete_all_objects(@table)
  end

  @doc """
  Returns the current size of the cache.
  """
  def count do
    case :ets.info(@table, :size) do
      :undefined -> 0
      size -> size
    end
  end
end
