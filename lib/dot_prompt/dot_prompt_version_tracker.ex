defmodule DotPrompt.VersionTracker do
  @moduledoc """
  Tracks and manages versions of prompts.
  """
  use GenServer
  require Logger

  @ets_table :prompt_access_log

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def record_access(prompt_key) do
    GenServer.cast(__MODULE__, {:record_access, prompt_key, "main"})
  end

  def record_access(prompt_key, branch) do
    GenServer.cast(__MODULE__, {:record_access, prompt_key, branch})
  end

  def flush_access_log do
    GenServer.call(__MODULE__, :flush_access_log)
  end

  def get_metadata do
    GenServer.call(__MODULE__, :get_metadata)
  end

  def register_version(prompt_key, version, branch) do
    GenServer.cast(__MODULE__, {:register_version, prompt_key, version, branch})
  end

  @impl true
  def init(opts) do
    :ets.new(@ets_table, [:set, :named_table, :public])

    prompts_dir =
      Keyword.get(opts, :prompts_dir) || Application.get_env(:dot_prompt, :prompts_dir)

    metadata = load_metadata(prompts_dir)

    state = %{
      metadata: metadata,
      prompts_dir: prompts_dir
    }

    Logger.info("VersionTracker initialized with metadata: #{inspect(Map.keys(metadata))}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:register_version, prompt_key, version, branch}, state) do
    updated_metadata =
      do_register_version(state.metadata, prompt_key, version, branch, state.prompts_dir)

    save_metadata(updated_metadata, state.prompts_dir)
    new_state = %{state | metadata: updated_metadata}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_access, prompt_key, branch}, state) do
    :ets.insert(@ets_table, {prompt_key, DateTime.utc_now(), branch})
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_metadata, _from, state) do
    {:reply, state.metadata, state}
  end

  @impl true
  def handle_call(:flush_access_log, _from, state) do
    access_entries = :ets.tab2list(@ets_table)

    updated_metadata = merge_access_log(state.metadata, access_entries, state.prompts_dir)
    save_metadata(updated_metadata, state.prompts_dir)

    :ets.delete_all_objects(@ets_table)

    new_state = %{state | metadata: updated_metadata}
    {:reply, updated_metadata, new_state}
  end

  defp do_register_version(metadata, prompt_key, version, branch, prompts_dir) do
    [category, name] = Path.split(prompt_key)
    skills = Map.get(metadata, :skills, %{})
    category_map = Map.get(skills, category, %{})
    version_map = Map.get(category_map, name, %{})

    archive_path = get_archive_path(prompts_dir, category, name, version)

    new_entry = %{
      "last_accessed" => format_datetime(DateTime.utc_now()),
      "branch" => branch,
      "archive_path" => archive_path
    }

    updated_version_map =
      version_map
      |> Map.put("v#{version}", new_entry)
      |> prune_versions(version)

    updated_category_map = Map.put(category_map, name, updated_version_map)
    updated_skills = Map.put(skills, category, updated_category_map)
    %{metadata | skills: updated_skills}
  end

  defp load_metadata(prompts_dir) do
    meta_path = Path.join(prompts_dir, ".github_poller_meta.json")

    if File.exists?(meta_path) do
      case File.read(meta_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, %{"skills" => skills}} ->
              %{skills: skills}

            {:ok, _} ->
              %{skills: %{}}

            {:error, _} ->
              Logger.warning("Failed to parse metadata file, starting fresh")
              %{skills: %{}}
          end

        {:error, _} ->
          Logger.warning("Failed to read metadata file, starting fresh")
          %{skills: %{}}
      end
    else
      %{skills: %{}}
    end
  end

  defp merge_access_log(metadata, access_entries, prompts_dir) do
    access_map =
      Enum.reduce(access_entries, %{}, fn entry, acc ->
        case entry do
          {prompt_key, timestamp, branch} ->
            Map.put(acc, prompt_key, {timestamp, branch})

          {prompt_key, timestamp} ->
            Map.put(acc, prompt_key, {timestamp, "main"})
        end
      end)

    metadata_skills = Map.get(metadata, :skills, %{})

    updated_skills =
      Enum.reduce(access_map, metadata_skills, fn {prompt_key, {accessed_at, branch}}, acc ->
        update_skill_metadata(acc, prompt_key, accessed_at, branch, prompts_dir)
      end)

    %{metadata | skills: updated_skills}
  end

  defp update_skill_metadata(skills, prompt_key, accessed_at, branch, prompts_dir) do
    [category, name] = Path.split(prompt_key)
    category_map = Map.get(skills, category, %{})
    version_map = Map.get(category_map, name, %{})

    current_versions = Map.keys(version_map)
    current = Enum.find(current_versions, &(&1 =~ ~r/^v\d+/))
    major = if current, do: extract_major(current), else: 1

    _current_entry =
      if current do
        Map.get(version_map, current)
      else
        nil
      end

    archive_path = get_archive_path(prompts_dir, category, name, major)

    new_entry = %{
      "last_accessed" => format_datetime(accessed_at),
      "branch" => branch,
      "archive_path" => archive_path
    }

    updated_version_map =
      version_map
      |> Map.put("v#{major}", new_entry)
      |> prune_versions(major)

    updated_category_map = Map.put(category_map, name, updated_version_map)
    Map.put(skills, category, updated_category_map)
  end

  defp extract_major(version) when is_binary(version) do
    case Integer.parse(String.replace(version, "v", "")) do
      {major, _} -> major
      _ -> 1
    end
  end

  defp get_archive_path(prompts_dir, category, name, major) do
    if category == "skills" do
      Path.join([prompts_dir, "skills/archive/#{name}_v#{major}.prompt"])
    else
      Path.join([prompts_dir, "archive/#{name}_v#{major}.prompt"])
    end
  end

  defp prune_versions(version_map, current_major) do
    version_list =
      Enum.map(version_map, fn {k, v} -> {k, v} end)
      |> Enum.sort_by(fn {version, _} -> extract_major(version) end, :desc)

    pruned =
      Enum.reduce(version_list, version_map, fn {version, entry}, acc ->
        major = extract_major(version)

        cond do
          major == current_major ->
            acc

          major > current_major ->
            should_delete =
              Enum.any?(acc, fn {v, _} ->
                v_major = extract_major(v)
                v_major == current_major
              end)

            if should_delete do
              Map.delete(acc, version)
            else
              acc
            end

          major < current_major ->
            last_accessed = entry["last_accessed"]

            if last_accessed do
              days_since = days_since_accessed(last_accessed)

              newer_exists =
                Enum.any?(acc, fn {v, _} ->
                  v_major = extract_major(v)
                  v_major > major
                end)

              if days_since > 30 and newer_exists do
                archive_count =
                  Enum.count(acc, fn {v, _} -> extract_major(v) < current_major end)

                if archive_count > 2 do
                  Map.delete(acc, version)
                else
                  acc
                end
              else
                acc
              end
            else
              acc
            end

          true ->
            acc
        end
      end)

    pruned
  end

  defp days_since_accessed(datetime_str) do
    case DateTime.from_iso8601(datetime_str) do
      {:ok, datetime, _} ->
        now = DateTime.utc_now()
        diff = DateTime.diff(now, datetime, :day)
        abs(diff)

      _ ->
        0
    end
  end

  defp format_datetime(%DateTime{} = dt) do
    DateTime.to_iso8601(dt)
  end

  defp format_datetime(datetime_str) when is_binary(datetime_str) do
    datetime_str
  end

  defp save_metadata(metadata, prompts_dir) do
    meta_path = Path.join(prompts_dir, ".github_poller_meta.json")
    dir = Path.dirname(meta_path)

    File.mkdir_p(dir)

    json = Jason.encode!(metadata, pretty: true)

    temp_path = meta_path <> ".tmp"
    File.write!(temp_path, json)
    File.rename(temp_path, meta_path)

    Logger.info("Saved metadata to #{meta_path}")
  end
end
