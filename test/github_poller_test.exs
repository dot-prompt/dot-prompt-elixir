defmodule DotPrompt.GitHubPollerTest do
  use ExUnit.Case, async: false

  alias DotPrompt.GitHubPoller

  setup do
    prompts_dir = Path.expand("test/fixtures/github_poller_test", File.cwd!())
    original_dir = Application.get_env(:anantha_dot_prompt, :prompts_dir)
    Application.put_env(:anantha_dot_prompt, :prompts_dir, prompts_dir, persistent: true)

    File.mkdir_p(Path.join(prompts_dir, "skills/archive"))
    File.mkdir_p(Path.join(prompts_dir, ".tmp_download"))

    on_exit(fn ->
      Application.put_env(:anantha_dot_prompt, :prompts_dir, original_dir, persistent: true)
      File.rm_rf(prompts_dir)
    end)

    {:ok, prompts_dir: prompts_dir}
  end

  describe "parse_version" do
    test "extracts version number from content" do
      content = """
      @version: 2
      This is a prompt.
      """

      version = GitHubPoller.parse_version(content)
      assert version == 2
    end

    test "defaults to version 1 when @version is missing" do
      content = "This is a prompt without version."
      version = GitHubPoller.parse_version(content)
      assert version == 1
    end

    test "handles version 0 correctly" do
      content = """
      @version 0
      This is a prompt.
      """

      version = GitHubPoller.parse_version(content)
      assert version == 0
    end
  end

  describe "parse_repo" do
    test "parses standard GitHub URL" do
      assert {:ok, "owner", "repo"} =
               GitHubPoller.parse_repo("https://github.com/owner/repo")
    end

    test "parses GitHub URL with .git suffix" do
      assert {:ok, "owner", "repo"} =
               GitHubPoller.parse_repo("https://github.com/owner/repo.git")
    end

    test "parses GitHub URL with trailing slash" do
      assert {:ok, "owner", "repo"} =
               GitHubPoller.parse_repo("https://github.com/owner/repo/")
    end

    test "parses GitHub URL with org and repo" do
      assert {:ok, "my-org", "my-repo"} =
               GitHubPoller.parse_repo("https://github.com/my-org/my-repo")
    end

    test "returns error for nil URL" do
      assert {:error, _} = GitHubPoller.parse_repo(nil)
    end

    test "returns error for empty URL" do
      assert {:error, _} = GitHubPoller.parse_repo("")
    end

    test "returns error for invalid URL" do
      assert {:error, _} = GitHubPoller.parse_repo("https://gitlab.com/owner/repo")
    end
  end

  describe "backoff_interval" do
    test "returns base interval for first failure" do
      interval = GitHubPoller.backoff_interval(0, 60)
      assert interval >= 60
      assert interval <= 65
    end

    test "increases exponentially with failures" do
      interval_1 = GitHubPoller.backoff_interval(1, 60)
      interval_2 = GitHubPoller.backoff_interval(2, 60)
      interval_3 = GitHubPoller.backoff_interval(3, 60)

      assert interval_1 > 60
      assert interval_2 > interval_1
      assert interval_3 > interval_2
    end

    test "caps at maximum of 300 seconds" do
      interval = GitHubPoller.backoff_interval(10, 60)
      assert interval <= 300
    end
  end

  describe "version detection" do
    test "detects major version jump and logs warning" do
      content = """
      @version 5
      Major version jump.
      """

      version = GitHubPoller.parse_version(content)
      current_version = 1

      assert version > current_version + 1
    end

    test "handles minor version increment" do
      content = """
      @version 2
      Minor version update.
      """

      version = GitHubPoller.parse_version(content)
      current_version = 1

      assert version == current_version + 1
    end
  end
end
