defmodule DotPrompt.VersionTrackerTest do
  use ExUnit.Case, async: false

  alias DotPrompt.VersionTracker

  setup do
    prompts_dir = Path.expand("test/fixtures/prompts", File.cwd!())
    original_dir = Application.get_env(:dot_prompt, :prompts_dir)
    Application.put_env(:dot_prompt, :prompts_dir, prompts_dir, persistent: true)

    # Start VersionTracker to ensure ETS table exists
    start_supervised!(VersionTracker)

    meta_dir = Path.join(prompts_dir, "prompts")
    File.mkdir_p(meta_dir)
    meta_path = Path.join(meta_dir, ".github_poller_meta.json")
    if File.exists?(meta_path), do: File.rm!(meta_path)
    :ets.delete_all_objects(:prompt_access_log)

    on_exit(fn ->
      Application.put_env(:dot_prompt, :prompts_dir, original_dir, persistent: true)
      File.rm_rf!(meta_dir)
    end)

    {:ok, meta_path: meta_path, prompts_dir: prompts_dir}
  end

  defp wait_for_cast do
    _ = :sys.get_state(VersionTracker)
  end

  describe "record_access" do
    test "inserts access record into ETS table" do
      VersionTracker.record_access("skills/my_skill")
      wait_for_cast()

      entries = :ets.tab2list(:prompt_access_log)
      assert length(entries) >= 1
      assert Enum.any?(entries, fn {k, _, _} -> k == "skills/my_skill" end)
    end

    test "updates existing entry with new timestamp" do
      VersionTracker.record_access("skills/my_skill")
      wait_for_cast()
      VersionTracker.record_access("skills/my_skill")
      wait_for_cast()

      entries = :ets.tab2list(:prompt_access_log)
      matching = Enum.filter(entries, fn {k, _, _} -> k == "skills/my_skill" end)
      assert length(matching) == 1
    end

    test "handles multiple different prompt keys" do
      VersionTracker.record_access("skills/skill1")
      wait_for_cast()
      VersionTracker.record_access("skills/skill2")
      wait_for_cast()

      entries = :ets.tab2list(:prompt_access_log)
      keys = Enum.map(entries, fn {k, _, _} -> k end)
      assert "skills/skill1" in keys
      assert "skills/skill2" in keys
    end
  end

  describe "flush_access_log" do
    test "merges ETS entries to metadata and returns updated metadata" do
      :ets.delete_all_objects(:prompt_access_log)

      VersionTracker.record_access("skills/test_skill")
      wait_for_cast()

      metadata = VersionTracker.flush_access_log()

      assert is_map(metadata)
      assert metadata.skills["skills"]["test_skill"]["v1"]["last_accessed"] != nil
    end

    test "clears ETS table after flushing" do
      VersionTracker.record_access("skills/test_skill")
      wait_for_cast()

      VersionTracker.flush_access_log()

      entries = :ets.tab2list(:prompt_access_log)
      keys = Enum.map(entries, fn {k, _, _} -> k end)
      refute "skills/test_skill" in keys
    end

    test "handles empty access log and returns metadata" do
      :ets.delete_all_objects(:prompt_access_log)

      metadata = VersionTracker.flush_access_log()

      assert is_map(metadata)
      assert Map.has_key?(metadata, :skills)
    end
  end

  describe "get_metadata" do
    test "returns current metadata state" do
      metadata = VersionTracker.get_metadata()
      assert is_map(metadata)
      assert Map.has_key?(metadata, :skills)
    end

    test "returns updated metadata after flush" do
      :ets.delete_all_objects(:prompt_access_log)

      VersionTracker.record_access("skills/test_skill")
      wait_for_cast()
      VersionTracker.flush_access_log()

      metadata = VersionTracker.get_metadata()
      assert metadata.skills["skills"]["test_skill"]["v1"] != nil
    end
  end

  describe "pruning logic" do
    test "keeps current version always" do
      :ets.delete_all_objects(:prompt_access_log)

      VersionTracker.record_access("skills/test_skill")
      wait_for_cast()
      metadata = VersionTracker.flush_access_log()

      assert metadata.skills["skills"]["test_skill"]["v1"] != nil
    end

    test "updates last_accessed timestamp when recording access" do
      :ets.delete_all_objects(:prompt_access_log)

      VersionTracker.record_access("skills/test_skill")
      wait_for_cast()
      metadata = VersionTracker.flush_access_log()

      v1_entry = metadata.skills["skills"]["test_skill"]["v1"]
      last_accessed = v1_entry["last_accessed"]
      {:ok, dt, _} = DateTime.from_iso8601(last_accessed)
      days_since = DateTime.diff(DateTime.utc_now(), dt, :day)
      assert days_since >= 0 and days_since <= 1
    end
  end

  describe "JSON round-trip" do
    test "flush_access_log returns metadata that can be serialized to JSON" do
      :ets.delete_all_objects(:prompt_access_log)

      VersionTracker.record_access("skills/test_skill")
      wait_for_cast()
      metadata = VersionTracker.flush_access_log()

      json = Jason.encode!(metadata)
      assert is_binary(json)
      {:ok, decoded} = Jason.decode(json)
      assert decoded["skills"]["skills"]["test_skill"]["v1"]["last_accessed"] != nil
    end
  end

  describe "edge cases" do
    test "returns metadata that is a map with :skills key" do
      metadata = VersionTracker.get_metadata()
      assert is_map(metadata)
      assert Map.has_key?(metadata, :skills)
    end

    test "multiple flushes accumulate metadata" do
      :ets.delete_all_objects(:prompt_access_log)

      VersionTracker.record_access("skills/skill1")
      wait_for_cast()
      VersionTracker.flush_access_log()

      VersionTracker.record_access("skills/skill2")
      wait_for_cast()
      metadata = VersionTracker.flush_access_log()

      assert metadata.skills["skills"]["skill1"]["v1"] != nil
      assert metadata.skills["skills"]["skill2"]["v1"] != nil
    end
  end
end
