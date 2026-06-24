defmodule DotPrompt.IntegrationTest do
  use ExUnit.Case, async: false

  test "compiles deep nesting (level 3)" do
    content = """
    if @level_1 is true do
      # Nesting Level 2
      case @level_2 do
        a: Level 2A
        # Nesting Level 3
        if @level_3 is true do
          Level 3 True
        else
          Level 3 False
        end @level_3
        b: Level 2B
      end @level_2
    end @level_1
    """

    params = %{level_1: true, level_2: "a", level_3: true}
    assert {:ok, %{prompt: result}} = DotPrompt.compile(content, params)
    assert result =~ "Level 2A"
    assert result =~ "Level 3 True"
    refute result =~ "Level 2B"
    refute result =~ "Level 3 False"

    params = %{level_1: true, level_2: "a", level_3: false}
    assert {:ok, %{prompt: result}} = DotPrompt.compile(content, params)
    assert result =~ "Level 3 False"
  end

  test "compiles all natural language operators in combinations" do
    content = """
    if @score above 90 do
      Grade: A
    elif @score min 80 do
      Grade: B
    elif @score between 70 and 79 do
      Grade: C
    elif @score max 69 do
      Grade: D/F
    end @score
    """

    assert {:ok, %DotPrompt.Result{prompt: res1}} = DotPrompt.compile(content, %{score: 95})
    assert res1 =~ "Grade: A"
    assert {:ok, %DotPrompt.Result{prompt: res2}} = DotPrompt.compile(content, %{score: 80})
    assert res2 =~ "Grade: B"
    assert {:ok, %DotPrompt.Result{prompt: res3}} = DotPrompt.compile(content, %{score: 75})
    assert res3 =~ "Grade: C"
    assert {:ok, %DotPrompt.Result{prompt: res4}} = DotPrompt.compile(content, %{score: 60})
    assert res4 =~ "Grade: D/F"
  end

  test "compiles complex case and vary combination" do
    content = """
    case @persona do
      tutor: #Tutor Persona
      if @expert is true do
        You are an expert tutor.
      else
        You are a helpful tutor.
      end @expert
      vary @style do
        encourage: Encourage the student.
        challenge: Challenge the student.
      end @style
      
      assistant: #Assistant Persona
      You are a helpful assistant.
    end @persona
    """

    params = %{persona: "tutor", expert: true, style: "challenge"}
    assert {:ok, %{prompt: result}} = DotPrompt.compile(content, params, seed: 1)
    assert result =~ "expert tutor"
    assert result =~ "Challenge the student."
    refute result =~ "assistant"
  end

  test "resolves compile-time variables in text blocks" do
    content = """
    Your level is @user_level.
    Your ID is @user_id.
    """

    params = %{user_level: "advanced", user_id: 42}
    assert {:ok, %{prompt: result}} = DotPrompt.render(content, params, %{})
    assert result =~ "Your level is advanced"
    assert result =~ "Your ID is 42"
  end

  test "handles empty blocks and edge cases" do
    content = """
    if @empty is true do
    end @empty
    Outside Text
    """

    assert {:ok, %{prompt: result}} = DotPrompt.compile(content, %{empty: true})
    assert result =~ "Outside Text"

    content = """
    case @empty do
    end @empty
    Outside Text
    """

    assert {:ok, %{prompt: result}} = DotPrompt.compile(content, %{empty: "anything"})
    assert result =~ "Outside Text"
  end

  describe "section annotations" do
    test "compile without annotated returns plain text without section markers" do
      content = """
      if @user_level is beginner do
        Welcome, new user!
      else
        Welcome back!
      end @user_level
      """

      assert {:ok, %{prompt: result}} = DotPrompt.compile(content, %{user_level: "beginner"})
      assert result =~ "Welcome, new user!"
      refute result =~ "[[section:"
      refute result =~ "[[/section]]"
    end

    test "compile with annotated: true includes section markers" do
      content = """
      if @user_level is beginner do
        Welcome, new user!
      else
        Welcome back!
      end @user_level
      """

      assert {:ok, %{prompt: result}} =
               DotPrompt.compile(content, %{user_level: "beginner"}, annotated: true)

      assert result =~ "[[section:branch:"
      assert result =~ "[[/section]]"
    end

    test "plain content without any conditionals has no section markers" do
      content = """
      You are a helpful assistant.
      Always be kind to users.
      """

      assert {:ok, %{prompt: result}} = DotPrompt.compile(content, %{})
      refute result =~ "[[section:"
      refute result =~ "[[/section]]"
    end

    test "plain content with annotated: true has no section markers" do
      content = """
      You are a helpful assistant.
      Always be kind to users.
      """

      assert {:ok, %{prompt: result}} = DotPrompt.compile(content, %{}, annotated: true)
      refute result =~ "[[section:"
      refute result =~ "[[/section]]"
    end

    test "section markers contain correct type for branch" do
      content = """
      if @mode is simple do
        Simple response.
      else
        Complex response.
      end @mode
      """

      assert {:ok, %{prompt: result}} =
               DotPrompt.compile(content, %{mode: "simple"}, annotated: true)

      assert result =~ "[[section:branch:"
    end

    test "section markers contain correct type for case" do
      content = """
      case @persona do
        tutor: You are a tutor.
        assistant: You are an assistant.
      end @persona
      """

      assert {:ok, %{prompt: result}} =
               DotPrompt.compile(content, %{persona: "tutor"}, annotated: true)

      assert result =~ "[[section:case:"
    end

    test "section markers contain correct type for vary" do
      content = """
      vary @style do
        formal: Please be formal.
        casual: Be casual.
      end @style
      """

      assert {:ok, %{prompt: result}} =
               DotPrompt.compile(content, %{style: "formal"}, annotated: true)

      assert result =~ "[[section:vary:"
    end
  end
end
