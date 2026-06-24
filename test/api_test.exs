defmodule DotPrompt.ApiTest do
  use ExUnit.Case, async: false

  @prompts_dir Path.expand("test/fixtures/api_test", File.cwd!())

  setup_all do
    original_dir = Application.get_env(:dot_prompt, :prompts_dir)
    Application.put_env(:dot_prompt, :prompts_dir, @prompts_dir)
    File.mkdir_p!(Path.join(@prompts_dir, "skills"))

    File.write!(Path.join(@prompts_dir, "demo.prompt"), """
    init do
      @version: 1
      def:
        mode: tutor
        description: A demo prompt for testing.
      params:
        @user: str = "Student"
    end init
    You are a helpful tutor teaching @user.
    """)

    File.write!(Path.join(@prompts_dir, "skills/anchoring.prompt"), """
    init do
      @version: 1
      def:
        mode: fragment
        match: Anchoring
    end init
    Anchoring Content
    """)

    on_exit(fn ->
      Application.put_env(:dot_prompt, :prompts_dir, original_dir)
      File.rm_rf!(@prompts_dir)
    end)

    :ok
  end

  describe "list functions" do
    test "list_prompts returns all prompt names" do
      prompts = DotPrompt.list_prompts()
      assert is_list(prompts)
      assert "demo" in prompts
      assert "skills/anchoring" in prompts
    end

    test "list_root_prompts returns only top-level prompts" do
      prompts = DotPrompt.list_root_prompts()
      assert "demo" in prompts
      refute "skills/anchoring" in prompts
    end

    test "list_fragment_prompts returns nested prompts" do
      prompts = DotPrompt.list_fragment_prompts()
      refute "demo" in prompts
      assert "skills/anchoring" in prompts
    end

    test "list_collections returns directories in prompts folder" do
      collections = DotPrompt.list_collections()
      assert "skills" in collections
    end
  end

  describe "schema/1" do
    test "returns structured metadata for a prompt" do
      assert {:ok, schema} = DotPrompt.schema("demo")
      assert schema.name == "demo"
      assert is_map(schema.params)
      assert is_map(schema.fragments)
      assert is_list(schema.docs) or is_binary(schema.docs) or is_nil(schema.docs)
    end

    test "returns error for non-existent prompt" do
      assert {:error, %{error: "prompt_not_found"}} = DotPrompt.schema("non_existent")
    end
  end

  describe "compile/3" do
    test "compiles inline content" do
      content = "Hello @name!"
      assert {:ok, %{prompt: result}} = DotPrompt.render(content, %{name: "World"}, %{})
      assert result =~ "Hello World!"
    end

    test "compiles by prompt name" do
      # Assuming demo.prompt exists and works
      assert {:ok, %{prompt: result}} = DotPrompt.render("demo", %{}, %{})
      assert result =~ "tutor"
    end

    test "returns syntax error for invalid content" do
      content = "if @a do\n  no end"
      assert {:error, %{error: "syntax_error"}} = DotPrompt.compile(content, %{a: true})
    end

    test "returns validation error for unknown variables" do
      content = """
      init do
        params:
          @a: str
      end init
      Using @b
      """

      assert {:error, %{error: "validation_error", message: message}} =
               DotPrompt.compile(content, %{a: "x"})

      assert message =~ "unknown_variable: b"
    end
  end

  describe "render/4" do
    test "performs full compilation and injection" do
      content = "Compile-time: @a. Runtime: {{b}}."
      params = %{a: "A"}
      runtime = %{b: "B"}
      assert {:ok, %{prompt: result}} = DotPrompt.render(content, params, runtime)
      assert result =~ "Compile-time: A"
      assert result =~ "Runtime: B"
    end
  end

  describe "v1.1 Advanced Compilation (Regressions)" do
    test "correctly matches numeric case branches" do
      content = """
      case @step do
      1: Step One
      2: Step Two
      end @step
      """

      assert {:ok, %{prompt: result}} = DotPrompt.compile(content, %{step: 1})
      assert result =~ "Step One"
      refute result =~ "Step Two"

      assert {:ok, %DotPrompt.Result{prompt: result2}} = DotPrompt.compile(content, %{step: 2})
      assert result2 =~ "Step Two"
      refute result2 =~ "Step One"
    end

    test "returns rich selections with full text for vary blocks" do
      content = """
      vary @style do
      fun: You are fun!
      sad: You are sad.
      end @style
      """

      opts = [annotated: true]

      assert {:ok, %{prompt: skeleton, vary_selections: selections}} =
               DotPrompt.compile(content, %{style: "fun"}, opts)

      # Verify rich metadata
      assert Map.has_key?(selections, "@style")
      assert selections["@style"].id == "fun"
      assert selections["@style"].text =~ "You are fun!"

      # Verify skeleton markers
      assert skeleton =~ "[[section:vary:0:0:_vary_@style:fun,sad:@style]]"
      assert skeleton =~ "[[vary:\"@style\"]]"
      assert skeleton =~ "[[/section]]"
    end

    test "respects collection match rules in compilation" do
      # Setup another skill
      File.write!(Path.join(@prompts_dir, "skills/milton.prompt"), """
      init do
        @version: 1
        def:
          mode: fragment
          match: Milton
      end init
      Milton Content
      """)

      content = """
      init do
        fragments:
          {matched}: static from: skills
            match: Milton
      end init
      Result:
      {matched}
      """

      # Compile the prompt which uses fragments

      assert {:ok, %{prompt: result}} = DotPrompt.compile(content, %{})
      assert result =~ "Milton Content"
      refute result =~ "Anchoring Content"
    end
  end

  describe "cache management" do
    test "invalidate_all_cache returns :ok" do
      assert :ok = DotPrompt.invalidate_all_cache()
      stats = DotPrompt.cache_stats()
      assert stats.structural == 0
    end

    test "cache_stats returns map of counts" do
      stats = DotPrompt.cache_stats()
      assert Enum.all?([:structural, :fragment, :vary], fn k -> Map.has_key?(stats, k) end)
    end
  end
end
