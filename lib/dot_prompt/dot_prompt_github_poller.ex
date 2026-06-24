defmodule DotPrompt.GitHubPoller do
  @moduledoc """
  Polls GitHub for changes in prompt files.
  """
  use GenServer
  require Logger

  alias DotPrompt.VersionTracker

  @base_url "https://api.github.com"
  @accept_header {"Accept", "application/vnd.github.v3+json"}
  @max_backoff_interval 300
  @backoff_jitter_range 5

  defp build_headers(nil), do: [@accept_header]
  defp build_headers(token), do: [@accept_header, {"Authorization", "Bearer #{token}"}]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    config = Keyword.get(opts, :github) || Application.get_env(:anantha_dot_prompt, :github) || []

    prompts_dir =
      Keyword.get(opts, :prompts_dir) || Application.get_env(:anantha_dot_prompt, :prompts_dir)

    state = %{
      repo_url: config[:repo_url],
      token: config[:token],
      branches: config[:branches] || ["main"],
      poll_interval: config[:poll_interval] || 60,
      prompts_dir: prompts_dir,
      branch_shas: %{},
      backoff: %{
        consecutive_failures: 0,
        next_retry_at: nil
      }
    }

    Logger.info(
      "[GitHubPoller] Starting with config: repo=#{state.repo_url}, branches=#{inspect(state.branches)}, interval=#{state.poll_interval}s"
    )

    schedule_poll(0)
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    case poll_branches(state) do
      {:ok, new_state} ->
        new_state = put_in(new_state.backoff.consecutive_failures, 0)
        new_state = put_in(new_state.backoff.next_retry_at, nil)
        schedule_poll(new_state.poll_interval)
        {:noreply, new_state}

      {:error, new_state} ->
        new_state = backoff_failure(new_state)

        schedule_poll(
          backoff_interval(new_state.backoff.consecutive_failures, state.poll_interval)
        )

        {:noreply, new_state}
    end
  end

  def handle_info({:retry, _from_backoff}, state) do
    case poll_branches(state) do
      {:ok, new_state} ->
        new_state = put_in(new_state.backoff.consecutive_failures, 0)
        new_state = put_in(new_state.backoff.next_retry_at, nil)
        schedule_poll(new_state.poll_interval)
        {:noreply, new_state}

      {:error, new_state} ->
        new_state = backoff_failure(new_state)
        interval = backoff_interval(new_state.backoff.consecutive_failures, state.poll_interval)
        schedule_retry(interval)
        {:noreply, new_state}
    end
  end

  defp poll_branches(state) do
    case parse_repo(state.repo_url) do
      {:ok, owner, repo} ->
        poll_all_branches(state, owner, repo)

      {:error, reason} ->
        Logger.error("[GitHubPoller] Failed to parse repo URL #{state.repo_url}: #{reason}")
        {:error, state}
    end
  end

  defp poll_all_branches(state, owner, repo) do
    VersionTracker.flush_access_log()

    results =
      Enum.map(state.branches, fn branch ->
        poll_branch(state, owner, repo, branch)
      end)

    failed = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(failed) do
      {:ok, state}
    else
      Logger.warning("[GitHubPoller] #{length(failed)} branch(es) failed to poll")
      {:error, state}
    end
  end

  defp poll_branch(state, owner, repo, branch) do
    case fetch_branch_sha(owner, repo, branch, state.token) do
      {:ok, sha} ->
        old_sha = Map.get(state.branch_shas, branch)

        if old_sha == sha do
          Logger.debug("[GitHubPoller] Branch #{branch} unchanged")
          {:ok, state}
        else
          Logger.info("[GitHubPoller] Branch #{branch} changed: #{old_sha} -> #{sha}")
          process_branch_changes(state, owner, repo, branch, sha)
        end

      {:error, reason} ->
        Logger.error("[GitHubPoller] Failed to fetch SHA for branch #{branch}: #{reason}")
        {:error, state}
    end
  end

  defp fetch_branch_sha(owner, repo, branch, token) do
    url = "#{@base_url}/repos/#{owner}/#{repo}/git/refs/heads/#{branch}"
    headers = build_headers(token)

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: %{"object" => %{"sha" => sha}}}} ->
        {:ok, sha}

      {:ok, %{status: 403}} ->
        {:error, "Rate limited"}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp process_branch_changes(state, owner, repo, branch, sha) do
    case fetch_tree(owner, repo, sha, state.token) do
      {:ok, tree} ->
        prompt_files =
          Enum.filter(tree, fn item ->
            String.ends_with?(item["path"], ".prompt")
          end)

        Logger.info("[GitHubPoller] Found #{length(prompt_files)} .prompt files in #{branch}")

        Enum.each(prompt_files, fn file ->
          process_prompt_file(state, owner, repo, branch, file)
        end)

        new_branch_shas = Map.put(state.branch_shas, branch, sha)
        new_state = %{state | branch_shas: new_branch_shas}
        {:ok, new_state}

      {:error, reason} ->
        Logger.error("[GitHubPoller] Failed to fetch tree for #{branch}: #{reason}")
        {:error, state}
    end
  end

  defp fetch_tree(owner, repo, sha, token) do
    url = "#{@base_url}/repos/#{owner}/#{repo}/git/trees/#{sha}?recursive=1"
    headers = build_headers(token)

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: %{"tree" => tree}}} ->
        {:ok, tree}

      {:ok, %{status: 403}} ->
        {:error, "Rate limited"}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp process_prompt_file(state, owner, repo, _branch, file) do
    sha = file["sha"]
    path = file["path"]

    case fetch_blob(owner, repo, sha, state.token) do
      {:ok, content} ->
        update_prompt_file(path, content, state)

      {:error, reason} ->
        Logger.warning("[GitHubPoller] Failed to fetch blob #{sha} for #{path}: #{reason}")
    end
  end

  defp fetch_blob(owner, repo, sha, token) do
    url = "#{@base_url}/repos/#{owner}/#{repo}/git/blobs/#{sha}"
    headers = build_headers(token)

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: %{"content" => content, "encoding" => "base64"}}} ->
        case Base.decode64(content) do
          {:ok, decoded} -> {:ok, decoded}
          :error -> {:error, "Invalid base64"}
        end

      {:ok, %{status: 403}} ->
        {:error, "Rate limited"}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp update_prompt_file(github_path, content, state) do
    prompts_dir = state.prompts_dir

    [category | rest_path] = Path.split(github_path)
    file_name = List.last(rest_path)
    name = Path.basename(file_name, ".prompt")

    dest_dir = Path.join([prompts_dir, category])
    File.mkdir_p(dest_dir)

    dest_path = Path.join(dest_dir, file_name)
    current_version = get_current_version(dest_path)
    new_version = parse_version(content)

    if new_version > current_version + 1 do
      Logger.warning(
        "[GitHubPoller] #{github_path} jumped to v#{new_version} (was v#{current_version}). Code may not be compatible. Serving new prompts anyway."
      )
    end

    if new_version > current_version do
      archive_path =
        Path.join([prompts_dir, category, "archive", "#{name}_v#{current_version}.prompt"])

      archive_dir = Path.dirname(archive_path)
      File.mkdir_p(archive_dir)

      if File.exists?(dest_path) do
        File.cp!(dest_path, archive_path)
        Logger.info("[GitHubPoller] Archived #{dest_path} to #{archive_path}")
      end
    end

    temp_dir = Path.join(prompts_dir, ".tmp_download")
    File.mkdir_p(temp_dir)

    temp_path = Path.join(temp_dir, file_name)
    File.write!(temp_path, content)
    File.rename(temp_path, dest_path)

    Logger.info("[GitHubPoller] Updated #{dest_path} (v#{new_version})")

    :ok
  end

  defp get_current_version(path) do
    if File.exists?(path) do
      case File.read(path) do
        {:ok, content} -> parse_version(content)
        {:error, _} -> 1
      end
    else
      1
    end
  end

  def parse_version(content) do
    case Regex.run(~r/@version:?\s+(\d+(?:\.\d+)*)/, content) do
      [_, version] ->
        case Integer.parse(version) do
          {major, "." <> _} -> major
          {major, _} -> major
          _ -> 1
        end

      nil ->
        1
    end
  end

  def parse_repo(nil), do: {:error, "repo_url is nil"}

  def parse_repo("") do
    {:error, "repo_url is empty"}
  end

  def parse_repo(url) do
    regex = ~r"github\.com[/:]([^/]+)/([^/]+?)(?:\.git)?/?$"

    case Regex.run(regex, url) do
      [_, owner, repo] -> {:ok, owner, String.trim_trailing(repo, "/")}
      nil -> {:error, "Invalid GitHub URL format"}
    end
  end

  def backoff_interval(consecutive_failures, base_interval) do
    jitter = :rand.uniform(@backoff_jitter_range)
    min(trunc(:math.pow(2, consecutive_failures)) * base_interval + jitter, @max_backoff_interval)
  end

  defp backoff_failure(state) do
    failures = state.backoff.consecutive_failures + 1

    next_retry_at =
      DateTime.add(DateTime.utc_now(), backoff_interval(failures, state.poll_interval), :second)

    %{
      state
      | backoff: %{
          consecutive_failures: failures,
          next_retry_at: next_retry_at
        }
    }
  end

  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms * 1000)
  end

  defp schedule_retry(interval_ms) do
    Process.send_after(self(), {:retry, :backoff}, interval_ms * 1000)
  end
end
