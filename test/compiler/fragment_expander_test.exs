defmodule DotPrompt.Compiler.FragmentExpanderTest do
  use ExUnit.Case, async: false

  alias DotPrompt.Compiler.FragmentExpander.Static
  alias DotPrompt.Compiler.FragmentExpander.Dynamic
  alias DotPrompt.Compiler.FragmentExpander.Collection

  @prompts_dir Path.expand("test/fixtures/fragment_expander", File.cwd!())

  setup_all do
    original_dir = Application.get_env(:dot_prompt, :prompts_dir)
    Application.put_env(:dot_prompt, :prompts_dir, @prompts_dir)
    File.mkdir_p!(Path.join(@prompts_dir, "fragments/tips"))

    # Simple greeting fragment
    File.write!(Path.join(@prompts_dir, "fragments/simple_greeting.prompt"), """
    init do
      @version: 1
      def:
        mode: fragment
    end init
    Hello! Welcome to our service.
    """)

    # Personalized greeting fragment with variables
    File.write!(Path.join(@prompts_dir, "fragments/personalized_greeting.prompt"), """
    init do
      @version: 1
      def:
        mode: fragment
      params:
        @name: str
    end init
    Hello @name!
    """)

    # Collection for tips
    File.write!(Path.join(@prompts_dir, "fragments/tips/_index.prompt"), """
    init do
      @version: 1
      def:
        mode: collection
    end init
    """)

    File.write!(Path.join(@prompts_dir, "fragments/tips/tip_1.prompt"), """
    init do
      @version: 1
      def:
        mode: fragment
        match: Tip
    end init
    Tip 1 Content
    """)

    # Malformed fragment for error testing
    File.mkdir_p!(Path.join(@prompts_dir, "malformed"))
    File.write!(Path.join(@prompts_dir, "malformed/bad.prompt"), "if @nonexistent is true do")

    on_exit(fn ->
      Application.put_env(:dot_prompt, :prompts_dir, original_dir)
      File.rm_rf!(@prompts_dir)
    end)

    {:ok, %{prompts_dir: @prompts_dir}}
  end

  describe "Static fragment expansion" do
    test "expands a static fragment" do
      assert {:ok, iodata, _used, _files_meta} = Static.expand("{fragments/simple_greeting}", %{})
      text = IO.iodata_to_binary(iodata)
      assert text =~ "Hello! Welcome to our service."
    end

    test "expands static fragment with variable interpolation" do
      params = %{name: "World"}

      assert {:ok, iodata, _used, _files_meta} =
               Static.expand("{fragments/personalized_greeting}", params)

      text = IO.iodata_to_binary(iodata)
      assert text =~ "@name"
    end
  end

  describe "Dynamic fragment expansion" do
    test "expands a dynamic fragment from params" do
      # Dynamic fragments interpolate runtime variables from params
      params = %{user_history: "Previous conversation:\n- Hello\n- Hi there!"}
      assert {:ok, content, _used, _files_meta} = Dynamic.expand("{{user_history}}", params)

      assert content =~ "Previous conversation:"
      assert content =~ "Hello"
      assert content =~ "Hi there!"
    end

    test "returns error when dynamic fragment variable not in params" do
      params = %{other_var: "something"}
      result = Dynamic.expand("{{user_history}}", params)

      assert {:error, error_msg} = result
      assert error_msg =~ "user_history"
    end

    test "handles different types of param values" do
      # String value
      assert {:ok, "hello world", _, _} =
               Dynamic.expand("{{greeting}}", %{greeting: "hello world"})

      # Integer value - key as atom
      assert {:ok, "42", _, _} = Dynamic.expand("{{count}}", %{count: 42})

      # List value - key as atom
      assert {:ok, "a, b, c", _, _} = Dynamic.expand("{{items}}", %{items: ["a", "b", "c"]})

      # String key
      assert {:ok, "hello world", _, _} =
               Dynamic.expand("{{greeting}}", %{"greeting" => "hello world"})
    end
  end

  describe "Collection fragment expansion" do
    setup do
      # Add another tip that shouldn't match
      File.write!(Path.join(@prompts_dir, "fragments/tips/tip_2.prompt"), """
      init do
        @version: 1
        def:
          mode: fragment
          match: Other
      end init
      Tip 2 Content
      """)

      :ok
    end

    test "expands all fragments in a collection" do
      assert {:ok, iodata, _used, _meta, count} =
               Collection.expand("{fragments/tips}", %{}, 0, %{}, 0, %{match: "all"})

      text = IO.iodata_to_binary(iodata)
      assert count == 2
      assert text =~ "Tip 1 Content"
      assert text =~ "Tip 2 Content"
    end

    test "respects match filter" do
      assert {:ok, iodata, _used, _meta, count} =
               Collection.expand("{fragments/tips}", %{}, 0, %{}, 0, %{match: "Tip"})

      text = IO.iodata_to_binary(iodata)
      assert count == 1
      assert text =~ "Tip 1 Content"
      refute text =~ "Tip 2 Content"
    end

    test "handles missing match variable gracefully" do
      # If match refers to a missing @var, it now returns a "none" header per user request
      assert {:ok, iodata, _used, _meta, count} =
               Collection.expand("{fragments/tips}", %{}, 0, %{}, 0, %{match: "@missing_skills"})

      text = IO.iodata_to_binary(iodata)
      assert count == 1
      assert text =~ "fragments/tips → none"
      assert text =~ "(none)"
    end
  end

  describe "Error handling" do
    test "handles missing fragment strictly" do
      assert {:error, _} = Static.expand("{nonexistent}", %{})
    end

    test "handles compilation errors strictly" do
      # Since we isolated setup, we know malformed/bad exists
      result = Static.expand("{malformed/bad}", %{})
      assert {:error, _} = result
    end
  end
end
