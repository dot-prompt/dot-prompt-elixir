defmodule DotPrompt.CacheTest do
  use ExUnit.Case, async: true

  alias DotPrompt.Cache.Fragment
  alias DotPrompt.Cache.Structural
  alias DotPrompt.Cache.Vary

  setup do
    # Initialize all cache tables before each test
    # Use :ets.info to check if table exists, if not create it
    init_if_not_exists(:dot_prompt_fragment_cache, &Fragment.init/0)
    init_if_not_exists(:dot_prompt_structural_cache, &Structural.init/0)
    init_if_not_exists(:dot_prompt_vary_cache, &Vary.init/0)

    # Clear caches to ensure clean state
    Fragment.clear()
    Structural.clear()
    Vary.clear()

    :ok
  end

  defp init_if_not_exists(table_name, init_fn) do
    case :ets.info(table_name, :name) do
      # Table already exists
      ^table_name -> :ok
      # Create table
      :undefined -> init_fn.()
    end
  end

  describe "Fragment Cache" do
    test "stores and retrieves compiled prompts correctly" do
      key = "fragments/simple_greeting"
      value = %{compiled: "Hello, World!", metadata: %{type: :static}}

      # Store in cache
      assert true = Fragment.put(key, value)

      # Retrieve from cache
      assert {:ok, result} = Fragment.get(key)
      assert result == value
    end

    test "returns error for non-existent key" do
      assert Fragment.get("non_existent") == :error
    end

    test "handles different cache key types" do
      # Test with string key
      Fragment.put("string_key", "string_value")
      assert {:ok, "string_value"} = Fragment.get("string_key")

      # Test with path-like key
      Fragment.put("prompts/fragments/greeting", "path_value")
      assert {:ok, "path_value"} = Fragment.get("prompts/fragments/greeting")

      # Test with tuple key
      Fragment.put({"prompt", "fragment"}, "tuple_value")
      assert {:ok, "tuple_value"} = Fragment.get({"prompt", "fragment"})
    end

    test "invalidates cache entries by path" do
      Fragment.put("fragments/greeting", "hello")
      Fragment.put("fragments/greeting_personalized", "hello personalized")
      Fragment.put("other/key", "other value")

      # Invalidate path containing "fragments"
      Fragment.invalidate_path("fragments")

      assert Fragment.get("fragments/greeting") == :error
      assert Fragment.get("fragments/greeting_personalized") == :error
      # Other entries should remain
      assert {:ok, "other value"} = Fragment.get("other/key")
    end

    test "clears all cache entries" do
      Fragment.put("key1", "value1")
      Fragment.put("key2", "value2")

      Fragment.clear()

      assert Fragment.get("key1") == :error
      assert Fragment.get("key2") == :error
    end

    test "returns correct count" do
      assert Fragment.count() == 0

      Fragment.put("key1", "value1")
      assert Fragment.count() == 1

      Fragment.put("key2", "value2")
      assert Fragment.count() == 2

      Fragment.clear()
      assert Fragment.count() == 0
    end
  end

  describe "Structural Cache" do
    test "stores and retrieves structural skeleton correctly" do
      key = {"demo", :params_hash}
      value = %{skeleton: "You are a...", metadata: %{version: 1}}

      Structural.put(key, value)

      assert {:ok, result} = Structural.get(key)
      assert result == value
    end

    test "returns error for non-existent key" do
      assert Structural.get({"non_existent", :hash}) == :error
    end

    test "invalidates by prompt name" do
      Structural.put({"demo", :hash1}, "value1")
      Structural.put({"demo", :hash2}, "value2")
      Structural.put({"other", :hash1}, "other_value")

      # Invalidate all entries for "demo"
      Structural.invalidate_name("demo")

      assert Structural.get({"demo", :hash1}) == :error
      assert Structural.get({"demo", :hash2}) == :error
      # Other prompt entries should remain
      assert {:ok, "other_value"} = Structural.get({"other", :hash1})
    end

    test "clears all cache entries" do
      Structural.put({"key1", :h1}, "value1")
      Structural.put({"key2", :h2}, "value2")

      Structural.clear()

      assert Structural.get({"key1", :h1}) == :error
      assert Structural.get({"key2", :h2}) == :error
    end

    test "returns correct count" do
      assert Structural.count() == 0

      Structural.put({"prompt1", :hash1}, "value1")
      assert Structural.count() == 1

      Structural.put({"prompt2", :hash2}, "value2")
      assert Structural.count() == 2

      Structural.clear()
      assert Structural.count() == 0
    end
  end

  describe "Vary Cache" do
    test "stores and retrieves vary branch content correctly" do
      prompt_name = "demo"
      vary_name = "level"
      branch_id = "beginner"
      content = "You are teaching beginner students."

      Vary.put(prompt_name, vary_name, branch_id, content)

      assert {:ok, result} = Vary.get(prompt_name, vary_name, branch_id)
      assert result == content
    end

    test "returns error for non-existent vary branch" do
      assert Vary.get("demo", "level", "non_existent") == :error
    end

    test "handles different vary branches" do
      Vary.put("demo", "level", "beginner", "beginner content")
      Vary.put("demo", "level", "advanced", "advanced content")
      Vary.put("demo", "style", "formal", "formal content")

      assert {:ok, "beginner content"} = Vary.get("demo", "level", "beginner")
      assert {:ok, "advanced content"} = Vary.get("demo", "level", "advanced")
      assert {:ok, "formal content"} = Vary.get("demo", "style", "formal")
    end

    test "invalidates all vary branches for a prompt" do
      Vary.put("demo", "level", "beginner", "beginner")
      Vary.put("demo", "level", "advanced", "advanced")
      Vary.put("demo", "style", "formal", "formal")
      Vary.put("other", "level", "beginner", "other beginner")

      # Invalidate all vary entries for "demo"
      Vary.invalidate_prompt("demo")

      assert Vary.get("demo", "level", "beginner") == :error
      assert Vary.get("demo", "level", "advanced") == :error
      assert Vary.get("demo", "style", "formal") == :error
      # Other prompt entries should remain
      assert {:ok, "other beginner"} = Vary.get("other", "level", "beginner")
    end

    test "clears all cache entries" do
      Vary.put("demo", "vary1", "branch1", "content1")
      Vary.put("demo", "vary2", "branch2", "content2")

      Vary.clear()

      assert Vary.get("demo", "vary1", "branch1") == :error
      assert Vary.get("demo", "vary2", "branch2") == :error
    end

    test "returns correct count" do
      assert Vary.count() == 0

      Vary.put("demo", "vary1", "branch1", "content1")
      assert Vary.count() == 1

      Vary.put("demo", "vary2", "branch2", "content2")
      assert Vary.count() == 2

      Vary.clear()
      assert Vary.count() == 0
    end
  end

  describe "Concurrent Access" do
    test "Fragment cache handles concurrent writes and reads" do
      parent = self()

      # Spawn multiple processes to write concurrently
      Enum.each(1..10, fn i ->
        spawn(fn ->
          key = "concurrent_key_#{i}"
          value = "value_#{i}"
          Fragment.put(key, value)
          send(parent, {:write_done, i})
        end)
      end)

      # Wait for all writes to complete
      Enum.each(1..10, fn _ ->
        receive do
          {:write_done, _} -> :ok
        end
      end)

      # Verify all entries were written correctly
      assert Fragment.count() == 10

      # Verify each entry was written correctly
      assert {:ok, "value_1"} = Fragment.get("concurrent_key_1")
      assert {:ok, "value_2"} = Fragment.get("concurrent_key_2")
      assert {:ok, "value_3"} = Fragment.get("concurrent_key_3")
      assert {:ok, "value_4"} = Fragment.get("concurrent_key_4")
      assert {:ok, "value_5"} = Fragment.get("concurrent_key_5")
      assert {:ok, "value_6"} = Fragment.get("concurrent_key_6")
      assert {:ok, "value_7"} = Fragment.get("concurrent_key_7")
      assert {:ok, "value_8"} = Fragment.get("concurrent_key_8")
      assert {:ok, "value_9"} = Fragment.get("concurrent_key_9")
      assert {:ok, "value_10"} = Fragment.get("concurrent_key_10")
    end

    test "Structural cache handles concurrent writes and reads" do
      parent = self()

      # Spawn multiple processes to write concurrently
      Enum.each(1..10, fn i ->
        spawn(fn ->
          key = {"prompt_#{i}", :hash}
          value = "value_#{i}"
          Structural.put(key, value)
          send(parent, {:write_done, i})
        end)
      end)

      # Wait for all writes to complete
      Enum.each(1..10, fn _ ->
        receive do
          {:write_done, _} -> :ok
        end
      end)

      # Verify all entries were written correctly
      assert Structural.count() == 10

      # Verify each entry was written correctly
      assert {:ok, "value_1"} = Structural.get({"prompt_1", :hash})
      assert {:ok, "value_2"} = Structural.get({"prompt_2", :hash})
      assert {:ok, "value_3"} = Structural.get({"prompt_3", :hash})
      assert {:ok, "value_4"} = Structural.get({"prompt_4", :hash})
      assert {:ok, "value_5"} = Structural.get({"prompt_5", :hash})
      assert {:ok, "value_6"} = Structural.get({"prompt_6", :hash})
      assert {:ok, "value_7"} = Structural.get({"prompt_7", :hash})
      assert {:ok, "value_8"} = Structural.get({"prompt_8", :hash})
      assert {:ok, "value_9"} = Structural.get({"prompt_9", :hash})
      assert {:ok, "value_10"} = Structural.get({"prompt_10", :hash})
    end

    test "Vary cache handles concurrent writes and reads" do
      parent = self()

      # Spawn multiple processes to write concurrently
      Enum.each(1..10, fn i ->
        spawn(fn ->
          Vary.put("demo", "vary_#{i}", "branch_#{i}", "content_#{i}")
          send(parent, {:write_done, i})
        end)
      end)

      # Wait for all writes to complete
      Enum.each(1..10, fn _ ->
        receive do
          {:write_done, _} -> :ok
        end
      end)

      # Verify all entries were written correctly
      assert Vary.count() == 10

      # Verify each entry was written correctly
      assert {:ok, "content_1"} = Vary.get("demo", "vary_1", "branch_1")
      assert {:ok, "content_2"} = Vary.get("demo", "vary_2", "branch_2")
      assert {:ok, "content_3"} = Vary.get("demo", "vary_3", "branch_3")
      assert {:ok, "content_4"} = Vary.get("demo", "vary_4", "branch_4")
      assert {:ok, "content_5"} = Vary.get("demo", "vary_5", "branch_5")
      assert {:ok, "content_6"} = Vary.get("demo", "vary_6", "branch_6")
      assert {:ok, "content_7"} = Vary.get("demo", "vary_7", "branch_7")
      assert {:ok, "content_8"} = Vary.get("demo", "vary_8", "branch_8")
      assert {:ok, "content_9"} = Vary.get("demo", "vary_9", "branch_9")
      assert {:ok, "content_10"} = Vary.get("demo", "vary_10", "branch_10")
    end
  end

  describe "Error Handling" do
    test "Fragment cache handles invalid operations gracefully" do
      # Test get on non-existent key
      assert Fragment.get("nonexistent") == :error

      # Test that put always returns true
      assert true = Fragment.put("key", "value")

      # Test that clear always returns true
      assert true = Fragment.clear()
    end

    test "Structural cache handles invalid operations gracefully" do
      # Test get on non-existent key
      assert Structural.get({"nonexistent", :hash}) == :error

      # Test that put always returns true
      assert true = Structural.put({"key", :hash}, "value")

      # Test that clear always returns true
      assert true = Structural.clear()
    end

    test "Vary cache handles invalid operations gracefully" do
      # Test get on non-existent branch
      assert Vary.get("nonexistent", "vary", "branch") == :error

      # Test that put always returns true
      assert true = Vary.put("prompt", "vary", "branch", "content")

      # Test that clear always returns true
      assert true = Vary.clear()
    end

    test "cache handles empty values" do
      Fragment.put("empty_key", "")
      assert {:ok, ""} = Fragment.get("empty_key")

      Structural.put({"prompt", :hash}, "")
      assert {:ok, ""} = Structural.get({"prompt", :hash})

      Vary.put("prompt", "vary", "branch", "")
      assert {:ok, ""} = Vary.get("prompt", "vary", "branch")
    end

    test "cache handles complex data structures" do
      complex_value = %{
        skeleton: "You are a...",
        fragments: [
          %{id: "greeting", content: "Hello"},
          %{id: "instructions", content: "Be helpful"}
        ],
        metadata: %{
          version: 1,
          params: [:user_level, :topic],
          vary: %{field: :level, branches: ["beginner", "advanced"]}
        }
      }

      Fragment.put("complex_key", complex_value)
      assert {:ok, result} = Fragment.get("complex_key")
      assert result == complex_value
    end
  end

  describe "Cache Key Generation" do
    test "Fragment cache key based on path" do
      # Simulate cache key generation based on prompt path
      path = "prompts/fragments/greeting"
      params = %{user: "Alice"}

      # Key could be path with params hash
      key = "#{path}:#{inspect(params)}"
      Fragment.put(key, "compiled content")

      assert {:ok, "compiled content"} = Fragment.get(key)
    end

    test "Structural cache key based on prompt name and params hash" do
      prompt_name = "demo"
      params_hash = :erlang.phash2(%{user_level: "beginner"})

      key = {prompt_name, params_hash}
      value = %{skeleton: "You are...", metadata: %{}}

      Structural.put(key, value)
      assert {:ok, ^value} = Structural.get(key)
    end

    test "Vary cache key based on prompt, vary field, and branch" do
      prompt_name = "demo"
      vary_field = "level"
      branch_id = "beginner"

      # Vary cache uses composite key
      Vary.put(prompt_name, vary_field, branch_id, "branch content")

      assert {:ok, "branch content"} = Vary.get(prompt_name, vary_field, branch_id)
    end
  end

  describe "Cache Invalidation Scenarios" do
    test "Fragment cache partial path invalidation" do
      Fragment.put("prompts/fragments/greeting", "greeting content")
      Fragment.put("prompts/fragments/farewell", "farewell content")
      Fragment.put("prompts/other/content", "other content")

      # Invalidate only fragments directory
      Fragment.invalidate_path("fragments")

      assert Fragment.get("prompts/fragments/greeting") == :error
      assert Fragment.get("prompts/fragments/farewell") == :error
      assert {:ok, "other content"} = Fragment.get("prompts/other/content")
    end

    test "Structural cache multiple prompts invalidation" do
      Structural.put({"prompt1", :hash1}, "value1")
      Structural.put({"prompt1", :hash2}, "value2")
      Structural.put({"prompt2", :hash1}, "value3")

      # Invalidate prompt1 only
      Structural.invalidate_name("prompt1")

      assert Structural.get({"prompt1", :hash1}) == :error
      assert Structural.get({"prompt1", :hash2}) == :error
      assert {:ok, "value3"} = Structural.get({"prompt2", :hash1})
    end

    test "Vary cache selective invalidation" do
      Vary.put("demo", "level", "beginner", "beginner content")
      Vary.put("demo", "level", "advanced", "advanced content")
      Vary.put("demo", "style", "formal", "formal content")
      Vary.put("other", "level", "beginner", "other content")

      # Invalidate only "level" vary for "demo"
      # Note: current implementation invalidates all varies for a prompt
      Vary.invalidate_prompt("demo")

      assert Vary.get("demo", "level", "beginner") == :error
      assert Vary.get("demo", "level", "advanced") == :error
      assert Vary.get("demo", "style", "formal") == :error
      # Other prompt should remain
      assert {:ok, "other content"} = Vary.get("other", "level", "beginner")
    end
  end
end
