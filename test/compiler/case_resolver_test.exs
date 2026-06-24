defmodule DotPrompt.Compiler.CaseResolverTest do
  use ExUnit.Case, async: false

  alias DotPrompt.Compiler.CaseResolver

  setup do
    DotPrompt.invalidate_all_cache()
    :ok
  end

  describe "resolve/2" do
    test "resolves case branch by string value" do
      branches = [
        {"formal", "Formal Response", [{:text, "You are speaking formally."}]},
        {"casual", "Casual Response", [{:text, "Hey there!"}]}
      ]

      assert [{:text, "You are speaking formally."}] = CaseResolver.resolve("formal", branches)
      assert [{:text, "Hey there!"}] = CaseResolver.resolve("casual", branches)
    end

    test "returns empty list when no branch matches" do
      branches = [
        {"formal", "Formal", [{:text, "Formal text"}]},
        {"casual", "Casual", [{:text, "Casual text"}]}
      ]

      assert [] = CaseResolver.resolve("unknown", branches)
    end

    test "handles integer values by converting to string" do
      branches = [
        {"1", "One", [{:text, "Number 1"}]},
        {"2", "Two", [{:text, "Number 2"}]}
      ]

      assert [{:text, "Number 1"}] = CaseResolver.resolve(1, branches)
      assert [{:text, "Number 2"}] = CaseResolver.resolve(2, branches)
    end

    test "handles branch with empty content" do
      branches = [
        {"empty", "Empty Branch", []}
      ]

      assert [] = CaseResolver.resolve("empty", branches)
    end

    test "handles nested if inside branch" do
      if_node = {:if, "@flag", "is true", [{:text, "Inside if"}], [], nil}
      branches = [{"with_if", "With If", [if_node]}]

      result = CaseResolver.resolve("with_if", branches)
      assert is_list(result)
      assert length(result) == 1
      assert elem(hd(result), 0) == :if
    end
  end

  describe "# prefix handling in case titles" do
    test "strips # prefix from case label in output" do
      content = """
      init do
        params:
          @level: enum[basic, advanced]
      end init
      case @level do
      basic: # Basic
      Simple explanation.
      advanced: # Advanced
      Detailed explanation.
      end @level
      """

      assert {:ok, %{prompt: result}} = DotPrompt.compile(content, %{level: "advanced"})
      # The # should be stripped from the label
      assert result =~ "Advanced"
      refute result =~ "# Advanced"
    end

    test "strips # prefix from case title with space" do
      content = """
      init do
        params:
          @mode: enum[default, casual]
      end init
      case @mode do
      default: # Default Case
      This is the default case.
      casual: Casual Response
      Hey there!
      end @mode
      """

      assert {:ok, %{prompt: result}} = DotPrompt.compile(content, %{mode: "default"})
      assert result =~ "Default Case"
      assert result =~ "This is the default case"
      # The # prefix should be stripped from the output
      refute result =~ "# Default"
    end

    test "strips # prefix from case title without space" do
      content = """
      init do
        params:
          @mode: enum[special, casual]
      end init
      case @mode do
      special: #Special
      This is special.
      casual: Casual Response
      Hey there!
      end @mode
      """

      assert {:ok, %{prompt: result}} = DotPrompt.compile(content, %{mode: "special"})
      assert result =~ "Special"
      assert result =~ "This is special"
      # The # prefix should be stripped from the output
      refute result =~ "#Special"
    end

    test "handles case title with multiple # prefixes" do
      content = """
      init do
        params:
          @type: enum[ultra, standard]
      end init
      case @type do
      ultra: ##ultra
      Ultra special.
      standard: Standard Response
      Normal.
      end @type
      """

      assert {:ok, %{prompt: result}} = DotPrompt.compile(content, %{type: "ultra"})
      assert result =~ "ultra"
      # At least one # should be stripped
      refute result =~ "##ultra"
    end
  end

  describe "integration with compiler" do
    test "compiles case block with matching branch" do
      content = """
      init do
        params:
          @mode: enum[formal, casual]
      end init
      case @mode do
      formal: You are formal.
      casual: Hey there!
      end @mode
      """

      assert {:ok, %{prompt: result}} = DotPrompt.compile(content, %{mode: "formal"})
      assert result =~ "You are formal."
      refute result =~ "Hey"
    end

    test "compiles case block selecting different branch" do
      content = """
      init do
        params:
          @mode: enum[formal, casual]
      end init
      case @mode do
      formal: You are formal.
      casual: Hey there!
      end @mode
      """

      assert {:ok, %{prompt: result}} = DotPrompt.compile(content, %{mode: "casual"})
      assert result =~ "Hey there!"
      refute result =~ "You are formal"
    end

    test "case branch title is included in output" do
      content = """
      init do
        params:
          @depth: enum[shallow, deep]
      end init
      case @depth do
      shallow: Shallow Answer
      Brief response.
      deep: Deep Answer
      Detailed explanation.
      end @depth
      """

      assert {:ok, %{prompt: result}} = DotPrompt.compile(content, %{depth: "deep"})
      assert result =~ "Deep Answer"
      assert result =~ "Detailed explanation"
    end

    test "case with atom keys in branches" do
      content = """
      init do
        params:
          @response_type: enum[json, text]
      end init
      case @response_type do
      json: Return JSON.
      text: Return plain text.
      end @response_type
      """

      assert {:ok, %{prompt: result}} = DotPrompt.compile(content, %{response_type: "json"})
      assert result =~ "JSON"
    end

    test "case with if inside branch" do
      content = """
      init do
        params:
          @mode: enum[formal, detailed]
          @expert: bool
      end init
      case @mode do
      formal: if @expert is true do
        You are a formal expert.
        else
        You are formal but learning.
        end @expert
      detailed: Detailed explanation mode.
      end @mode
      """

      assert {:ok, %{prompt: result}} =
               DotPrompt.compile(content, %{mode: "formal", expert: true})

      assert result =~ "formal expert"
      refute result =~ "learning"
    end
  end
end
