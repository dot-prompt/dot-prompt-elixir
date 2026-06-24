defmodule DotPrompt.Compiler.FragmentExpander.CollectionTest do
  use ExUnit.Case, async: false
  alias DotPrompt.Compiler.FragmentExpander.Collection

  @prompts_dir Path.expand("test/fixtures/collection_test", File.cwd!())

  setup_all do
    original_dir = Application.get_env(:dot_prompt, :prompts_dir)
    Application.put_env(:dot_prompt, :prompts_dir, @prompts_dir)
    # Ensure fixtures exist
    File.mkdir_p!(Path.join(@prompts_dir, "skills"))

    test_skills = Path.join(@prompts_dir, "skills")

    File.write!(Path.join(test_skills, "_index.prompt"), """
    init do
      @version: 1
      def:
        mode: collection
    end init
    """)

    File.write!(Path.join(test_skills, "anchoring.prompt"), """
    init do
      @version: 1
      def:
        mode: fragment
        match: Anchoring
      params:
        @selected: list
    end init
    Anchoring Content
    """)

    File.write!(Path.join(test_skills, "milton_model.prompt"), """
    init do
      @version: 1
      def:
        mode: fragment
        match: Milton Model
      params:
        @selected: list
    end init
    Milton Model Content
    """)

    File.write!(Path.join(test_skills, "meta_model.prompt"), """
    init do
      @version: 1
      def:
        mode: fragment
        match: Meta Model
      params:
        @selected: list
    end init
    Meta Model Content
    """)

    on_exit(fn ->
      Application.put_env(:dot_prompt, :prompts_dir, original_dir)
      File.rm_rf!(@prompts_dir)
    end)

    {:ok, %{dir: @prompts_dir}}
  end

  describe "expand/6" do
    test "matches all fragments with match: all" do
      rules = %{match: "all", order: "ascending"}
      assert {:ok, text, _, _, count} = Collection.expand("{skills}", %{}, 0, %{}, 0, rules)

      assert count == 3
      text_str = IO.iodata_to_binary(text)
      assert text_str =~ "Anchoring Content"
      assert text_str =~ "Meta Model Content"
      assert text_str =~ "Milton Model Content"
    end

    test "matches specific fragments with match: @var" do
      rules = %{match: "@selected"}
      params = %{selected: ["Anchoring", "Meta Model"]}
      assert {:ok, text, _, _, count} = Collection.expand("{skills}", params, 0, %{}, 0, rules)

      assert count == 2
      text_str = IO.iodata_to_binary(text)
      assert text_str =~ "Anchoring Content"
      assert text_str =~ "Meta Model Content"
      refute text_str =~ "Milton Model Content"
    end

    test "matches with regex using matchRe" do
      rules = %{matchRe: "M.*", order: "ascending"}
      assert {:ok, text, _, _, count} = Collection.expand("{skills}", %{}, 0, %{}, 0, rules)

      assert count == 2
      text_str = IO.iodata_to_binary(text)
      assert text_str =~ "Meta Model Content"
      assert text_str =~ "Milton Model Content"
      refute text_str =~ "Anchoring Content"
    end

    test "respects limit and order" do
      rules = %{match: "all", limit: "1", order: "descending"}
      assert {:ok, text, _, _, count} = Collection.expand("{skills}", %{}, 0, %{}, 0, rules)

      assert count == 1
      text_str = IO.iodata_to_binary(text)
      # descending alphabetic: milton, meta, anchoring -> first is milton
      assert text_str =~ "Milton Model Content"
      refute text_str =~ "Meta Model Content"
      refute text_str =~ "Anchoring Content"
    end

    test "returns error when collection directory does not exist (missing_index)" do
      # The no_index fixture directory exists but has a prompt file that compiles
      # To trigger collection_not_found error, we need a non-existent directory
      rules = %{match: "all"}
      result = Collection.expand("{nonexistent_collection}", %{}, 0, %{}, 0, rules)

      # Should return an error indicating the collection directory is not found
      assert {:error, error_msg} = result
      assert error_msg =~ "collection_not_found"
      assert error_msg =~ "nonexistent_collection"
    end

    test "returns ok with none header when no fragments match the given criteria (collection_no_match)" do
      # Use a match pattern that doesn't match any existing fragments in the skills collection
      rules = %{match: "NonExistentPatternThatMatchesNothing"}
      result = Collection.expand("{skills}", %{}, 0, %{}, 0, rules)

      # The collection exists and has index, but no fragments match the criteria
      # This returns ok with "(none)" header text and count = 1 (the none item)
      assert {:ok, text, _, _, count} = result
      text_str = IO.iodata_to_binary(text)
      assert text_str =~ "(none)"
      assert count == 1
    end

    test "matches with regex using matchRe with @variable interpolation" do
      # Test that @pattern variable is interpolated correctly
      rules = %{matchRe: "@pattern"}
      params = %{pattern: "M.*"}
      assert {:ok, text, _, _, count} = Collection.expand("{skills}", params, 0, %{}, 0, rules)

      assert count == 2
      text_str = IO.iodata_to_binary(text)
      assert text_str =~ "Meta Model Content"
      assert text_str =~ "Milton Model Content"
      refute text_str =~ "Anchoring Content"
    end

    test "matches with regex using matchRe with @variable containing complex pattern" do
      # Test that a more complex regex pattern works via variable interpolation
      rules = %{matchRe: "@pattern"}
      params = %{pattern: "[A-M].*"}
      assert {:ok, text, _, _, count} = Collection.expand("{skills}", params, 0, %{}, 0, rules)

      # [A-M] should match Anchoring (A), Meta Model (M), and Milton Model (M)
      assert count == 3
      text_str = IO.iodata_to_binary(text)
      assert text_str =~ "Meta Model Content"
      assert text_str =~ "Anchoring Content"
      assert text_str =~ "Milton Model Content"
    end

    test "interpolates @variable in matchRe pattern correctly" do
      # Verify that @pattern gets replaced with the actual pattern value
      rules = %{matchRe: "@filter"}
      params = %{filter: "Milton.*"}
      assert {:ok, text, _, _, count} = Collection.expand("{skills}", params, 0, %{}, 0, rules)

      assert count == 1
      text_str = IO.iodata_to_binary(text)
      assert text_str =~ "Milton Model Content"
      refute text_str =~ "Meta Model Content"
    end
  end
end
