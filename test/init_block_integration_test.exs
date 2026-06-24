defmodule DotPrompt.InitBlockIntegrationTest do
  use ExUnit.Case, async: false

  setup do
    # Invalidate cache before each test to avoid test pollution
    DotPrompt.invalidate_all_cache()
    :ok
  end

  describe "init block params through compile pipeline" do
    test "string params are correctly interpolated" do
      content = """
      init do
        params:
          @user_name: str
      end init
      Hello @user_name, welcome!
      """

      params = %{user_name: "Alice"}
      assert {:ok, %{prompt: result}} = DotPrompt.render(content, params, %{})
      assert result =~ "Hello Alice"
      assert result =~ "welcome!"
    end

    test "number params are correctly interpolated" do
      content = """
      init do
        params:
          @score: int
      end init
      Your score is @score
      """

      params = %{score: 42}
      assert {:ok, %{prompt: result}} = DotPrompt.render(content, params, %{})
      assert result =~ "Your score is 42"
    end

    test "boolean params work in conditionals" do
      content = """
      init do
        params:
          @is_premium: bool
      end init
      if @is_premium is true do
        You have premium access.
      else
        You have basic access.
      end @is_premium
      """

      params = %{is_premium: true}
      assert {:ok, %{prompt: result}} = DotPrompt.render(content, params, %{})
      assert result =~ "premium access"
      refute result =~ "basic access"

      params = %{is_premium: false}
      assert {:ok, %{prompt: result}} = DotPrompt.render(content, params, %{})
      assert result =~ "basic access"
      refute result =~ "premium access"
    end

    test "enum params work in vary blocks" do
      content = """
      init do
        params:
          @style: enum[formal, casual, friendly]
      end init
      vary @style do
        formal: Please be formal in your response.
        casual: Feel free to be casual.
        friendly: Be warm and friendly.
      end @style
      """

      # The vary block should compile - params from init are used to validate
      # Seed ensures deterministic selection
      assert {:ok, %{prompt: result}} = DotPrompt.compile(content, %{}, seed: 1)
      assert is_binary(result)
    end

    test "params with defaults are used when not provided" do
      content = """
      init do
        params:
          @greeting: str = "Hello"
      end init
      @greeting
      """

      # No params provided - should use default
      assert {:ok, %{prompt: result}} = DotPrompt.render(content, %{}, %{})
      assert result =~ "Hello"
    end
  end

  describe "init block def section through compile pipeline" do
    test "def section is parsed" do
      content = """
      init do
        @version: 2
        def:
          description: A test prompt
      end init
      Test content here.
      """

      assert {:ok, %{prompt: result}} = DotPrompt.compile(content, %{})
      assert result =~ "Test content"
    end
  end

  describe "init block params section through compile pipeline" do
    test "params section with type declarations work" do
      content = """
      init do
        params:
          @temperature: float
          @max_tokens: int
      end init
      Use temperature @temperature and max @max_tokens tokens.
      """

      params = %{temperature: 0.7, max_tokens: 1000}
      assert {:ok, %{prompt: result}} = DotPrompt.render(content, params, %{})
      assert result =~ "temperature 0.7"
      assert result =~ "max 1000 tokens"
    end

    test "params section with enum values work" do
      content = """
      init do
        params:
          @tone: enum[encouraging, neutral, critical]
      end init
      case @tone do
        encouraging: Be encouraging.
        neutral: Be neutral.
        critical: Be critical.
      end @tone
      """

      params = %{tone: "encouraging"}
      assert {:ok, %{prompt: result}} = DotPrompt.compile(content, params)
      assert result =~ "Be encouraging"

      params = %{tone: "critical"}
      assert {:ok, %{prompt: result}} = DotPrompt.compile(content, params)
      assert result =~ "Be critical"
    end

    test "params section with range constraints work" do
      content = """
      init do
        params:
          @level: int[1..10]
      end init
      Operating at level @level
      """

      params = %{level: 5}
      assert {:ok, %{prompt: result}} = DotPrompt.render(content, params, %{})
      assert result =~ "level 5"
    end
  end

  describe "init block docs section through compile pipeline" do
    test "docs section is parsed but not rendered in output" do
      content = """
      init do
        docs do
          This is documentation for the prompt.
          It provides context about usage.
        end docs
      end init
      Actual prompt content here.
      """

      assert {:ok, %{prompt: result}} = DotPrompt.compile(content, %{})
      assert result =~ "Actual prompt content"
      refute result =~ "documentation"
      refute result =~ "context about usage"
    end
  end

  describe "init block with full pipeline (compile + render)" do
    test "compile then render with params" do
      content = """
      init do
        params:
          @system_prompt: str
      end init
      @system_prompt
      """

      compile_params = %{system_prompt: "You are a helpful assistant."}
      runtime = %{}

      # render returns {:ok, result}
      assert {:ok, %{prompt: result}} = DotPrompt.render(content, compile_params, runtime)
      assert result =~ "You are a helpful assistant"
    end

    test "render with empty runtime works" do
      content = """
      init do
        params:
          @greeting: str
      end init
      @greeting, world!
      """

      compile_params = %{greeting: "Hello"}
      runtime = %{}

      assert {:ok, %{prompt: result}} = DotPrompt.render(content, compile_params, runtime)
      assert result =~ "Hello"
      assert result =~ "world"
    end
  end

  describe "error handling for malformed init blocks" do
    test "undeclared param used in body returns error" do
      content = """
      init do
        params:
          @declared: str
      end init
      Using @undeclared
      """

      assert {:error, %{error: "validation_error"}} = DotPrompt.compile(content, %{})
    end
  end

  describe "complex init block scenarios" do
    test "multiple param types in single init block" do
      content = """
      init do
        params:
          @name: str
          @age: int
          @is_active: bool
          @role: enum[admin, user, guest]
      end init
      User: @name
      Age: @age
      Active: @is_active
      Role: @role
      """

      params = %{
        name: "John",
        age: 30,
        is_active: true,
        role: "admin"
      }

      assert {:ok, %{prompt: result}} = DotPrompt.render(content, params, %{})
      assert result =~ "User: John"
      assert result =~ "Age: 30"
      assert result =~ "Active: true"
      assert result =~ "Role: admin"
    end

    test "init block with all sections compiles correctly" do
      content = """
      init do
        @version: 1
        params:
          @mode: enum[simple, detailed]
        docs do
          This is the documentation.
        end docs
      end init
      vary @mode do
        simple: Keep it brief.
        detailed: Provide full details.
      end @mode
      """

      # Test that the full init block compiles - seed ensures deterministic vary selection
      assert {:ok, %{prompt: result}} = DotPrompt.compile(content, %{}, seed: 1)
      assert is_binary(result)
    end
  end
end
