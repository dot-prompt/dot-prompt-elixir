defmodule DotPrompt.Compiler.VaryCompositorTest do
  use ExUnit.Case, async: false

  alias DotPrompt.Compiler.VaryCompositor

  setup do
    DotPrompt.invalidate_all_cache()
    :ok
  end

  describe "resolve/3" do
    test "resolves vary slots with seed" do
      skeleton = "Intro: [[vary:\"intro\"]]"

      vary_map = %{
        "intro" => [
          {"a", "label", [{:text, "Hello A"}]},
          {"b", "label", [{:text, "Hello B"}]}
        ]
      }

      assert VaryCompositor.resolve(skeleton, vary_map, 0) =~ "Hello A"
      assert VaryCompositor.resolve(skeleton, vary_map, 1) =~ "Hello B"
    end
  end

  describe "resolve_full/3" do
    test "returns selections map with vary variable names" do
      skeleton = "Intro: [[vary:\"intro_style\"]]"

      vary_map = %{
        "intro_style" => [
          {"formal", "label", [{:text, "Formal greeting"}]},
          {"casual", "label", [{:text, "Casual greeting"}]}
        ]
      }

      {_result, selections} = VaryCompositor.resolve_full(skeleton, vary_map, 0)
      assert selections == %{"intro_style" => %{id: "formal", text: "Formal greeting"}}
    end

    test "same seed produces same result" do
      skeleton = "Intro: [[vary:\"style\"]]"

      vary_map = %{
        "style" => [
          {"a", "label", [{:text, "Option A"}]},
          {"b", "label", [{:text, "Option B"}]}
        ]
      }

      {result1, _} = VaryCompositor.resolve_full(skeleton, vary_map, 42)
      {result2, _} = VaryCompositor.resolve_full(skeleton, vary_map, 42)
      assert result1 == result2
    end

    test "different seeds produce different results" do
      skeleton = "Intro: [[vary:\"style\"]]"

      vary_map = %{
        "style" => [
          {"a", "label", [{:text, "Option A"}]},
          {"b", "label", [{:text, "Option B"}]}
        ]
      }

      results =
        Enum.map([0, 1, 2, 3], fn seed ->
          {result, _} = VaryCompositor.resolve_full(skeleton, vary_map, seed)
          result
        end)

      assert length(Enum.uniq(results)) > 1
    end
  end

  describe "integration with compiler" do
    test "compiles vary block" do
      content = """
      init do
        params:
          @style: enum[formal, casual]
      end init
      vary @style do
      formal: Formal greeting.
      casual: Casual greeting.
      end @style
      """

      assert {:ok, %{prompt: result}} =
               DotPrompt.compile(content, %{style: "formal"}, seed: 1)

      assert is_binary(result)
    end

    test "vary block with nested case inside" do
      content = """
      init do
        params:
          @style: enum[a, b]
          @depth: enum[1, 2]
      end init
      vary @style do
      a: case @depth do
        1: A1
        2: A2
        end @depth
      b: case @depth do
        1: B1
        2: B2
        end @depth
      end @style
      """

      assert {:ok, %{prompt: result}} =
               DotPrompt.compile(content, %{style: "a", depth: 1}, seed: 1)

      assert is_binary(result)
    end

    test "named branches are resolved" do
      content = """
      init do
        params:
          @tone: enum[encouraging, challenging]
      end init
      vary @tone do
      encouraging: You are doing great!
      challenging: Push yourself harder.
      end @tone
      """

      assert {:ok, %{prompt: result}} =
               DotPrompt.compile(content, %{tone: "encouraging"}, seed: 1)

      assert result =~ "great" or result =~ "harder"
    end

    test "vary with nested if" do
      content = """
      init do
        params:
          @style: enum[formal, casual]
          @expert: bool
      end init
      vary @style do
      formal: if @expert is true do
        Expert formal.
        else
        Beginner formal.
        end @expert
      casual: if @expert is true do
        Expert casual.
        else
        Beginner casual.
        end @expert
      end @style
      """

      assert {:ok, %{prompt: result}} =
               DotPrompt.compile(content, %{style: "formal", expert: true}, seed: 1)

      assert is_binary(result)
    end

    test "seed produces deterministic vary selection" do
      content = """
      init do
        params:
          @style: enum[a, b, c]
      end init
      vary @style do
      a: A
      b: B
      c: C
      end @style
      """

      DotPrompt.invalidate_all_cache()
      {:ok, %DotPrompt.Result{prompt: r1}} = DotPrompt.compile(content, %{}, seed: 42)

      DotPrompt.invalidate_all_cache()
      {:ok, %DotPrompt.Result{prompt: r2}} = DotPrompt.compile(content, %{}, seed: 42)

      assert r1 == r2
    end
  end
end
