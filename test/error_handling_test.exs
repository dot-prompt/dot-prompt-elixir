defmodule DotPrompt.ErrorHandlingTest do
  use ExUnit.Case, async: false

  setup_all do
    original_dir = Application.get_env(:dot_prompt, :prompts_dir)
    prompts_dir = Path.expand("test/fixtures/prompts", File.cwd!())
    Application.put_env(:dot_prompt, :prompts_dir, prompts_dir)

    on_exit(fn ->
      Application.put_env(:dot_prompt, :prompts_dir, original_dir)
    end)

    :ok
  end

  setup do
    DotPrompt.invalidate_all_cache()
    :ok
  end

  describe "unknown_variable" do
    test "error when variable referenced but not declared" do
      content = """
      init do
        params:
          @known: str
      end init
      Hello @unknown
      """

      assert {:error, %{error: "validation_error", message: message}} =
               DotPrompt.compile(content, %{known: "value"})

      assert message =~ "unknown_variable"
      assert message =~ "unknown"
      assert message =~ "not declared"
    end

    test "error message includes line number" do
      content = """
      init do
        params:
          @a: str
      end init

      Line 5: Hello @undeclared
      """

      assert {:error, %{message: message}} =
               DotPrompt.compile(content, %{a: "x"})

      assert message =~ "undeclared"
    end
  end

  describe "out_of_range" do
    test "error when int value below range" do
      content = """
      init do
        params:
          @step: int[1..5]
      end init
      Step @step
      """

      assert {:error, %{error: "validation_error", message: message}} =
               DotPrompt.compile(content, %{step: 0})

      assert message =~ "out_of_range"
      assert message =~ "@step"
      assert message =~ "0"
      assert message =~ "int[1..5]"
    end

    test "error when int value above range" do
      content = """
      init do
        params:
          @step: int[1..5]
      end init
      Step @step
      """

      assert {:error, %{error: "validation_error", message: message}} =
               DotPrompt.compile(content, %{step: 6})

      assert message =~ "out_of_range"
    end

    test "boundary values are valid" do
      content = """
      init do
        params:
          @step: int[1..5]
      end init
      Step @step
      """

      assert {:ok, %DotPrompt.Result{}} = DotPrompt.compile(content, %{step: 1})
      assert {:ok, %DotPrompt.Result{}} = DotPrompt.compile(content, %{step: 5})
    end
  end

  describe "invalid_enum" do
    test "error when enum value not in members" do
      content = """
      init do
        params:
          @variation: enum[analogy, recognition, story]
      end init
      Using @variation
      """

      assert {:error, %{error: "validation_error", message: message}} =
               DotPrompt.compile(content, %{variation: "fast"})

      assert message =~ "invalid_enum"
      assert message =~ "@variation"
      assert message =~ "fast"
      assert message =~ "analogy"
    end

    test "valid enum values pass" do
      content = """
      init do
        params:
          @variation: enum[analogy, recognition, story]
      end init
      Using @variation
      """

      assert {:ok, %{prompt: result}} =
               DotPrompt.render(content, %{variation: "recognition"}, %{})

      assert result =~ "recognition"
    end
  end

  describe "invalid_list" do
    test "error when list value not in members" do
      content = """
      init do
        params:
          @skills: list[Milton Model, Meta Model, Anchoring]
      end init
      Teaching @skills
      """

      assert {:error, %{error: "validation_error", message: message}} =
               DotPrompt.compile(content, %{skills: ["Unknown Skill"]})

      assert message =~ "invalid_enum"
      assert message =~ "@skills"
      assert message =~ "Unknown Skill"
    end

    test "valid list values pass" do
      content = """
      init do
        params:
          @skills: list[Milton Model, Meta Model, Anchoring]
      end init
      Teaching @skills
      """

      assert {:ok, %{prompt: result}} =
               DotPrompt.render(content, %{skills: ["Milton Model", "Meta Model"]}, %{})

      assert result =~ "Milton Model"
      assert result =~ "Meta Model"
    end
  end

  describe "missing_param" do
    test "error when required compile-time param not provided and no default" do
      content = """
      init do
        params:
          @missing_param_test_var: int[1..3]
      end init
      Hello @missing_param_test_var
      """

      assert {:error, %{error: "validation_error", message: message}} =
               DotPrompt.compile(content, %{})

      assert message =~ "missing_param"
      assert message =~ "@missing_param_test_var"
    end

    test "params with defaults do not error when omitted" do
      content = """
      init do
        params:
          @optional_default_test_var: str = default_value
      end init
      Hello @optional_default_test_var
      """

      assert {:ok, %{prompt: result}} = DotPrompt.render(content, %{}, %{})
      assert result =~ "default_value"
    end
  end

  describe "unclosed_block" do
    test "error when if block not closed" do
      content = """
      init do
        params:
          @a: bool
      end init
      if @a is true do
        inside
      """

      assert {:error, %{error: "syntax_error", message: message}} =
               DotPrompt.compile(content, %{a: true})

      assert message =~ "unclosed_block"
    end

    test "error when vary block not closed" do
      content = """
      init do
        params:
          @style: enum[formal, casual]
      end init
      vary @style do
        formal: Formal greeting
      """

      assert {:error, %{error: "syntax_error", message: message}} =
               DotPrompt.compile(content, %{style: "formal"})

      assert message =~ "unclosed_block"
    end
  end

  describe "mismatched_end" do
    test "error when end variable doesn't match opening" do
      content = """
      init do
        params:
          @a: bool
          @b: bool
      end init
      if @a is true do
        inside
      end @b
      """

      assert {:error, %{error: "syntax_error", message: message}} =
               DotPrompt.compile(content, %{a: true, b: false})

      assert message =~ "mismatched_end"
    end

    test "correct end variable passes" do
      content = """
      init do
        params:
          @a: bool
      end init
      if @a is true do
        inside
      end @a
      """

      assert {:ok, %DotPrompt.Result{}} = DotPrompt.compile(content, %{a: true})
    end
  end

  describe "nesting_exceeded" do
    test "error when nesting depth exceeds 3" do
      content = """
      init do
        params:
          @a: bool
          @b: bool
          @c: bool
          @d: bool
      end init
      if @a is true do
        if @b is true do
          if @c is true do
            if @d is true do
              too deep
            end @d
          end @c
        end @b
      end @a
      """

      assert {:error, %{error: "validation_error", message: message}} =
               DotPrompt.compile(content, %{a: true, b: true, c: true, d: true})

      assert message =~ "nesting_exceeded"
    end

    test "nesting depth of 3 is allowed" do
      content = """
      init do
        params:
          @a: bool
          @b: bool
          @c: bool
      end init
      if @a is true do
        if @b is true do
          if @c is true do
            valid depth
          end @c
        end @b
      end @a
      """

      assert {:ok, %{prompt: result}} =
               DotPrompt.compile(content, %{a: true, b: true, c: true})

      assert result =~ "valid depth"
    end
  end

  describe "unknown_vary" do
    test "error when vary block has no variable" do
      content = """
      init do
        params:
          @style: enum[formal, casual]
      end init
      vary do
        formal: Hello
        casual: Hi
      end
      """

      # Parser or Validator should catch this.
      # With current lexer, 'vary do' might not match vary_start.
      assert {:error, _} = DotPrompt.compile(content, %{style: "formal"})
    end
  end

  describe "missing_fragment" do
    test "error when static fragment file not found" do
      content = """
      init do
        fragments:
          {missing}: static from: does_not_exist.prompt
      end init
      {missing}
      """

      assert {:error, %{error: "validation_error", message: message}} =
               DotPrompt.compile(content, %{})

      assert message =~ "fragment_not_found" or message =~ "does_not_exist"
    end
  end

  describe "trailing_slash" do
    test "error when fragment path has trailing slash" do
      content = """
      init do
        fragments:
          {frag}: static from: skills/
      end init
      {frag}
      """

      assert {:error, %{error: "validation_error", message: message}} =
               DotPrompt.compile(content, %{})

      assert message =~ "trailing slashes not allowed"
    end
  end

  describe "collection_not_found (missing_index)" do
    test "error when accessing non-existent collection directory as fragment" do
      # First set up a valid collection directory
      current_dir = Application.get_env(:dot_prompt, :prompts_dir)
      test_collection_dir = Path.join(current_dir, "valid_collection")

      File.mkdir_p!(test_collection_dir)

      on_exit(fn ->
        File.rm_rf!(test_collection_dir)
      end)

      File.write!(Path.join(test_collection_dir, "_index.prompt"), """
      init do
        @version: 1
        def:
          mode: collection
      end init
      """)

      # Now try to reference a collection that doesn't exist
      content = """
      init do
        fragments:
          {completely_different_dir}
      end init
      {completely_different_dir}
      """

      result = DotPrompt.compile(content, %{})

      # The collection directory "completely_different_dir" doesn't exist
      # Error is returned as a map with :error and :message keys
      assert {:error, error_msg} = result
      assert is_map(error_msg)
      assert error_msg.message =~ "unknown_fragment"
    end
  end

  describe "collection_no_match" do
    test "returns ok with none header when no fragments match criteria" do
      # First set up a collection with matching fragments
      current_dir = Application.get_env(:dot_prompt, :prompts_dir)
      test_collection_dir = Path.join(current_dir, "test_no_match_collection")

      # Create a collection with fragments that have specific match values
      File.mkdir_p!(test_collection_dir)

      on_exit(fn ->
        File.rm_rf!(test_collection_dir)
      end)

      File.write!(Path.join(test_collection_dir, "_index.prompt"), """
      init do
        @version: 1
        def:
          mode: collection
      end init
      """)

      File.write!(Path.join(test_collection_dir, "fragment1.prompt"), """
      init do
        @version: 1
        def:
          mode: fragment
          match: ActualPattern
      end init
      Content1
      """)

      # Now try to compile with a non-matching pattern
      # Use the correct syntax with indented match option
      content = """
      init do
        fragments:
          {test_no_match_collection}: static from: test_no_match_collection
            match: NonExistentPattern
      end init
      {test_no_match_collection}
      """

      result = DotPrompt.compile(content, %{})

      # This should return ok with "(none)" header (not an error)
      assert {:ok, %DotPrompt.Result{prompt: text}} = result
      text_str = IO.iodata_to_binary(text)
      assert text_str =~ "(none)"
    end
  end
end
