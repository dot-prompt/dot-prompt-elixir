defmodule DotPrompt.Cache.Vary do
  @moduledoc """
  ETS-based cache for vary branch content.
  """
  use GenServer

  @table :dot_prompt_vary_cache

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

  def get(prompt_name, vary_name, branch_id) do
    key = {to_string(prompt_name), to_string(vary_name), to_string(branch_id)}

    case :ets.lookup(@table, key) do
      [{^key, value}] -> {:ok, value}
      [] -> :error
    end
  end

  def put(prompt_name, vary_name, branch_id, content) do
    key = {to_string(prompt_name), to_string(vary_name), to_string(branch_id)}
    :ets.insert(@table, {key, content})
  end

  def invalidate_prompt(prompt_name) do
    prompt_name_str = to_string(prompt_name)
    # Manual match specification for {{prompt_name, _, _}, _}
    pattern = [{{{prompt_name_str, :_, :_}, :_}, [], [true]}]
    :ets.select_delete(@table, pattern)
  end

  def clear do
    :ets.delete_all_objects(@table)
  end

  def count do
    case :ets.info(@table, :size) do
      :undefined -> 0
      size -> size
    end
  end
end
