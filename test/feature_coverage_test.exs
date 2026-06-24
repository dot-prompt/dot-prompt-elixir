defmodule DotPrompt.FeatureCoverageTest do
  use ExUnit.Case, async: false

  @prompts_dir Path.expand("test/fixtures/feature_coverage", File.cwd!())

  setup_all do
    original_dir = Application.get_env(:dot_prompt, :prompts_dir)
    Application.put_env(:dot_prompt, :prompts_dir, @prompts_dir)

    # Create fixture directory structure
    File.mkdir_p!(@prompts_dir)
    File.mkdir_p!(Path.join(@prompts_dir, "fragments"))
    File.mkdir_p!(Path.join(@prompts_dir, "skills/embedded_commands"))
    File.mkdir_p!(Path.join(@prompts_dir, "skills/presuppositions"))

    # intro.prompt
    File.write!(
      Path.join(@prompts_dir, "intro.prompt"),
      """
      init do
        @version: 1.0
        def:
          mode: intro
          description: Welcome message for new users
        params:
          @user_name: str
        docs do
        Welcome message for new users
        end docs
      end init
      Welcome, @user_name!
      """
    )

    # teacher_explanation.prompt
    File.write!(
      Path.join(@prompts_dir, "teacher_explanation.prompt"),
      """
      init do
        @version: 1.0
        def:
          mode: teacher
          description: Teacher mode for NLP training
        params:
          @input_mode: enum[teach_flow, question]
          @pattern_step: int[1..5] = 1
          @current_step_name: str
      end init
      Step: @pattern_step of 5
      Step name: @current_step_name
      """
    )

    # qa_response.prompt
    File.write!(
      Path.join(@prompts_dir, "qa_response.prompt"),
      """
      init do
        @version: 1.0
        def:
          mode: qa_response
          description: Answer user questions about NLP
        params:
          @context: str
        docs do
        Answer user questions about NLP
        end docs
      end init
      Context: @context
      """
    )

    # fragments/user_context.prompt
    File.write!(
      Path.join(@prompts_dir, "fragments/user_context.prompt"),
      """
      init do
        @version: 1.0
        params:
          @user_name: str = "Learner"
      end init
      **Name**: @user_name
      """
    )

    # skills/embedded_commands/_index.prompt
    File.write!(
      Path.join(@prompts_dir, "skills/embedded_commands/_index.prompt"),
      """
      init do
        @version: 1.0
        fragments:
          {.*}: static from: skills/embedded_commands
            match: all
      end init
      Embedded Commands
      {.*}
      """
    )

    # skills/embedded_commands/tone_shift.prompt
    File.write!(
      Path.join(@prompts_dir, "skills/embedded_commands/tone_shift.prompt"),
      """
      init do
        @version: 1.0
      end init
      Tone shift in embedded commands
      """
    )

    # skills/presuppositions/_index.prompt
    File.write!(
      Path.join(@prompts_dir, "skills/presuppositions/_index.prompt"),
      """
      init do
        @version: 1.0
        fragments:
          {.*}: static from: skills/presuppositions
            match: all
      end init
      Presuppositions
      {.*}
      """
    )

    # skills/presuppositions/existential.prompt
    File.write!(
      Path.join(@prompts_dir, "skills/presuppositions/existential.prompt"),
      """
      init do
        @version: 1.0
      end init
      Existential presuppositions
      """
    )

    # roleplay_leadership.prompt
    File.write!(
      Path.join(@prompts_dir, "roleplay_leadership.prompt"),
      """
      init do
        @version: 1.0
      end init
      Leadership roleplay content
      """
    )

    # roleplay_patient.prompt
    File.write!(
      Path.join(@prompts_dir, "roleplay_patient.prompt"),
      """
      init do
        @version: 1.0
      end init
      Patient roleplay content
      """
    )

    # analysis_agent.prompt
    File.write!(
      Path.join(@prompts_dir, "analysis_agent.prompt"),
      """
      init do
        @version: 1.0
      end init
      Analysis agent content
      """
    )

    on_exit(fn ->
      Application.put_env(:dot_prompt, :prompts_dir, original_dir)
      File.rm_rf!(@prompts_dir)
    end)

    :ok
  end

  setup do
    DotPrompt.invalidate_all_cache()
    :ok
  end

  describe "@version declaration" do
    test "intro.prompt has correct version format" do
      assert {:ok, result} = DotPrompt.render("intro", %{}, %{})
      assert result.version == "1.0"
      assert result.major == 1
    end

    test "teacher_explanation.prompt has version 1.0" do
      assert {:ok, result} = DotPrompt.render("teacher_explanation", %{}, %{})
      assert result.version == "1.0"
      assert result.major == 1
    end
  end

  describe "def: mode and description" do
    test "intro.prompt has correct mode and description" do
      assert {:ok, schema} = DotPrompt.schema("intro")
      assert schema.mode == "intro"
      assert schema.description =~ "Welcome message"
    end

    test "teacher_explanation.prompt has correct metadata" do
      assert {:ok, schema} = DotPrompt.schema("teacher_explanation")
      assert schema.mode == "teacher"
      assert schema.description =~ "Teacher mode"
    end

    test "qa_response.prompt has correct metadata" do
      assert {:ok, schema} = DotPrompt.schema("qa_response")
      assert schema.mode == "qa_response"
      assert schema.description =~ "Answer user questions"
    end
  end

  describe "params with all type systems" do
    test "str type - intro.prompt" do
      assert {:ok, schema} = DotPrompt.schema("intro")
      assert schema.params["user_name"][:type] == :str
      assert schema.params["user_name"][:lifecycle] == :runtime
    end

    test "enum type - teacher_explanation.prompt" do
      assert {:ok, schema} = DotPrompt.schema("teacher_explanation")
      assert schema.params["input_mode"][:type] == :enum
      assert schema.params["input_mode"][:values] == ["teach_flow", "question"]
      assert schema.params["input_mode"][:lifecycle] == :compile
    end

    test "int[a..b] type - teacher_explanation.prompt" do
      assert {:ok, schema} = DotPrompt.schema("teacher_explanation")
      assert schema.params["pattern_step"][:type] == :int
      assert schema.params["pattern_step"][:range] == [1, 5]
      assert schema.params["pattern_step"][:lifecycle] == :compile
    end

    test "bool type - conditionals work correctly" do
      content = """
      init do
        @version: 1
        @is_active: bool
      end init
      if @is_active is true do
        Active content
      else
        Inactive content
      end @is_active
      """

      assert {:ok, %{prompt: r1}} = DotPrompt.compile(content, %{is_active: true})
      assert r1 =~ "Active content"
      refute r1 =~ "Inactive content"
      assert {:ok, %{prompt: r2}} = DotPrompt.compile(content, %{is_active: false})
      refute r2 =~ "Active content"
      assert r2 =~ "Inactive content"
    end
  end

  describe "docs block" do
    test "intro.prompt has docs" do
      assert {:ok, schema} = DotPrompt.schema("intro")
      assert schema.docs =~ "Welcome message"
    end

    test "qa_response.prompt has docs" do
      assert {:ok, schema} = DotPrompt.schema("qa_response")
      assert schema.docs =~ "NLP"
    end
  end

  describe "if/elif/else control flow" do
    test "basic if true branch" do
      content = """
      init do
        @version: 1
        @show_extra: bool
      end init
      Base content
      if @show_extra is true do
      Extra content
      end @show_extra
      """

      assert {:ok, %{prompt: r1}} = DotPrompt.compile(content, %{show_extra: true})
      assert r1 =~ "Extra content"
      assert {:ok, %{prompt: r2}} = DotPrompt.compile(content, %{show_extra: false})
      refute r2 =~ "Extra content"
    end

    test "if with elif chain - all operators" do
      content = """
      init do
        @version: 1
        @score: int
      end init
      if @score above 90 do
      Grade A
      elif @score min 80 do
      Grade B
      elif @score between 70 and 79 do
      Grade C
      elif @score max 69 do
      Grade D/F
      else
      No grade
      end @score
      """

      assert {:ok, %{prompt: r1}} = DotPrompt.compile(content, %{score: 95})
      assert r1 =~ "Grade A"
      assert {:ok, %{prompt: r2}} = DotPrompt.compile(content, %{score: 80})
      assert r2 =~ "Grade B"
      assert {:ok, %{prompt: r3}} = DotPrompt.compile(content, %{score: 75})
      assert r3 =~ "Grade C"
      assert {:ok, %{prompt: r4}} = DotPrompt.compile(content, %{score: 60})
      assert r4 =~ "Grade D/F"
    end

    test "if with enum - is operator" do
      content = """
      init do
        @version: 1
        @mode: enum[teach, quiz]
      end init
      if @mode is teach do
      Teaching content
      elif @mode is quiz do
      Quiz content
      end @mode
      """

      assert {:ok, %{prompt: r1}} = DotPrompt.compile(content, %{mode: "teach"})
      assert r1 =~ "Teaching content"
      assert {:ok, %{prompt: r2}} = DotPrompt.compile(content, %{mode: "quiz"})
      assert r2 =~ "Quiz content"
    end

    test "if with enum - not operator" do
      content = """
      init do
        @version: 1
        @mode: enum[a, b, c]
      end init
      if @mode not a do
      Not A branch
      end @mode
      """

      assert {:ok, %{prompt: r1}} = DotPrompt.compile(content, %{mode: "b"})
      assert r1 =~ "Not A branch"
      assert {:ok, %{prompt: r2}} = DotPrompt.compile(content, %{mode: "a"})
      refute r2 =~ "Not A branch"
    end
  end

  describe "case deterministic branching" do
    test "basic case with enum" do
      content = """
      init do
        @version: 1
        @level: enum[beginner, intermediate, advanced]
      end init
      case @level do
      beginner: Welcome, new learner!
      intermediate: Welcome back!
      advanced: Welcome, expert!
      end @level
      """

      assert {:ok, %{prompt: r1}} = DotPrompt.compile(content, %{level: "beginner"})
      assert r1 =~ "new learner"
      assert {:ok, %{prompt: r2}} = DotPrompt.compile(content, %{level: "advanced"})
      assert r2 =~ "expert"
    end

    test "case with int range" do
      content = """
      init do
        @version: 1
        @step: int[1..5]
      end init
      case @step do
      1: First step
      2: Second step
      3: Third step
      4: Fourth step
      5: Fifth step
      end @step
      """

      for step <- 1..5 do
        assert {:ok, %{prompt: r}} = DotPrompt.compile(content, %{step: step})
        assert r =~ "step"
        refute r =~ "[[section:"
      end
    end

    test "case with title after colon" do
      content = """
      init do
        @version: 1
        @mode: enum[teach, quiz]
      end init
      case @mode do
      teach: Teacher Mode
      Welcome to teaching mode.
      quiz: Quiz Mode
      Time for questions.
      end @mode
      """

      assert {:ok, %{prompt: r}} = DotPrompt.compile(content, %{mode: "teach"})
      assert r =~ "Teacher Mode"
      assert r =~ "Welcome to teaching"
    end
  end

  describe "vary non-deterministic branching" do
    test "basic vary with enum" do
      content = """
      init do
        @version: 1
        @style: enum[formal, casual, friendly]
      end init
      vary @style do
      formal: Please be formal in your response.
      casual: Be casual and relaxed.
      friendly: Be warm and friendly.
      end @style
      """

      for style <- ["formal", "casual", "friendly"] do
        assert {:ok, %{prompt: _, vary_selections: s}} =
                 DotPrompt.compile(content, %{style: style})

        assert is_map(s)
      end
    end

    test "vary with seed for reproducibility" do
      content = """
      init do
        @version: 1
        @style: enum[a, b, c]
      end init
      vary @style do
      a: Option A
      b: Option B
      c: Option C
      end @style
      """

      assert {:ok, r1} = DotPrompt.compile(content, %{}, seed: 123)
      assert {:ok, r2} = DotPrompt.compile(content, %{}, seed: 123)
      assert r1.prompt == r2.prompt
    end

    test "multiple vary blocks with single seed" do
      content = """
      init do
        @version: 1
        @style: enum[formal, casual]
        @tone: enum[warm, neutral]
      end init
      vary @style do
      formal: Be formal.
      casual: Be casual.
      end @style
      vary @tone do
      warm: Be warm.
      neutral: Be neutral.
      end @tone
      """

      assert {:ok, %{vary_selections: s}} =
               DotPrompt.compile(content, %{style: "formal", tone: "neutral"}, seed: 42)

      assert Map.has_key?(s, "@style")
      assert Map.has_key?(s, "@tone")
    end
  end

  describe "nested control flow (max 3 levels)" do
    test "nested case inside case" do
      content = """
      init do
        @version: 1
        @track: enum[analogy, recognition]
        @step: int[1..3]
      end init
      case @track do
      analogy:
      case @step do
      1: Analogy intro
      2: Analogy deepen
      3: Analogy examples
      end @step
      recognition:
      case @step do
      1: Recognition intro
      2: Recognition deepen
      3: Recognition examples
      end @step
      end @track
      """

      assert {:ok, %{prompt: r}} = DotPrompt.compile(content, %{track: "analogy", step: 2})
      assert r =~ "Analogy deepen"
      refute r =~ "Recognition"
    end

    test "3-level nesting works" do
      content = """
      init do
        @version: 1
        @level1: bool
        @level2: enum[a, b]
        @level3: bool
      end init
      if @level1 is true do
      Level1
      case @level2 do
      a:
      if @level3 is true do
      Level3True
      else
      Level3False
      end @level3
      b: Level2B
      end @level2
      end @level1
      """

      assert {:ok, %{prompt: r}} =
               DotPrompt.compile(content, %{level1: true, level2: "a", level3: true})

      assert r =~ "Level1"
      assert r =~ "Level3True"
    end
  end

  describe "comments (stripped at compile time)" do
    test "single line comment is stripped" do
      content = """
      init do
        @version: 1
      end init
      # This is a comment
      Visible content
      """

      assert {:ok, %{prompt: r}} = DotPrompt.compile(content, %{})
      assert r =~ "Visible content"
      refute r =~ "This is a comment"
    end
  end

  describe "single file fragments" do
    test "static fragment from file" do
      assert {:ok, result} = DotPrompt.render("fragments/user_context", %{}, %{})
      assert result.prompt =~ "Name"
    end
  end

  describe "collection fragments" do
    test "collection with filter exact match" do
      assert {:ok, result} = DotPrompt.render("skills/embedded_commands/_index", %{}, %{})
      assert result.prompt =~ "Embedded Commands"
    end

    test "collection with all fragments" do
      assert {:ok, result} = DotPrompt.render("skills/presuppositions/_index", %{}, %{})
      assert result.prompt =~ "Presuppositions"
    end
  end

  describe "response contracts" do
    test "response block in prompt body" do
      content = """
      init do
        @version: 1
      end init
      Do the task.
      response do
        {"result": "string", "count": 42}
      end response
      """

      assert {:ok, result} = DotPrompt.compile(content, %{})
      assert result.response_contract != nil
    end

    test "validate_output with valid response" do
      contract = %{
        "name" => %{type: "string", required: true},
        "age" => %{type: "number", required: true}
      }

      assert :ok =
               DotPrompt.validate_output(
                 ~s({"name": "Alice", "age": 30}),
                 contract
               )
    end

    test "validate_output with invalid response" do
      contract = %{
        "name" => %{type: "string", required: true}
      }

      assert {:error, _} =
               DotPrompt.validate_output(
                 ~s({"other": "value"}),
                 contract
               )
    end
  end

  describe "schema extraction" do
    test "extracts params correctly" do
      assert {:ok, schema} = DotPrompt.schema("teacher_explanation")
      assert Map.has_key?(schema.params, "pattern_step")
      assert Map.has_key?(schema.params, "current_step_name")
    end

    test "returns error for non-existent prompt" do
      assert {:error, %{error: "prompt_not_found"}} = DotPrompt.schema("nonexistent_prompt")
    end
  end

  describe "list functions" do
    test "list_prompts includes all prompts" do
      prompts = DotPrompt.list_prompts()
      assert "teacher_explanation" in prompts
      assert "intro" in prompts
    end
  end

  describe "compilation options" do
    test "annotated: true includes section markers" do
      content = """
      init do
        @version: 1
        @mode: enum[a, b]
      end init
      case @mode do
      a: Content A
      b: Content B
      end @mode
      """

      {:ok, r} = DotPrompt.compile(content, %{mode: "a"}, annotated: true)
      assert r.prompt =~ "[[section:"
    end
  end

  describe "error handling" do
    test "unknown_variable returns validation error" do
      content = """
      init do
        @version: 1
        params:
          @known: str
      end init
      Unknown @unknown variable
      """

      assert {:error, %{error: "validation_error", message: msg}} =
               DotPrompt.compile(content, %{known: "value"})

      assert msg =~ "unknown_variable"
    end

    test "syntax_error for unclosed block" do
      content = """
      init do
        @version: 1
      end init
      if @a is true do
      No end
      """

      assert {:error, %{error: "syntax_error"}} =
               DotPrompt.compile(content, %{a: true})
    end
  end

  describe "inline content compilation" do
    test "compiles inline prompt file" do
      assert {:ok, result} = DotPrompt.render("intro", %{user_name: "World"}, %{})
      assert result.prompt =~ "World"
    end

    test "compiles inline with newlines" do
      content = """
      init do
        @version: 1
      end init
      Line 1
      Line 2
      """

      assert {:ok, %{prompt: r}} = DotPrompt.compile(content, %{})
      assert r =~ "Line 1"
      assert r =~ "Line 2"
    end
  end

  describe "token counting" do
    test "returns compiled_tokens in result" do
      assert {:ok, result} = DotPrompt.compile("Simple content", %{})
      assert is_integer(result.compiled_tokens)
    end
  end

  describe "multi-turn teaching simulation" do
    test "teacher_explanation renders all step names" do
      steps = ["introduce", "explain", "example", "student_try", "feedback"]

      for step <- steps do
        params = %{current_step_name: step}
        assert {:ok, result} = DotPrompt.render("teacher_explanation", params, %{})
        assert result.prompt =~ "Step name: #{step}", "Failed for step: #{step}"
      end
    end

    test "teacher_explanation with pattern steps" do
      for step <- 1..5 do
        params = %{pattern_step: step}
        assert {:ok, result} = DotPrompt.render("teacher_explanation", params, %{})
        assert result.prompt =~ "Step: #{step} of 5"
      end
    end
  end

  describe "roleplay prompts" do
    test "roleplay_leadership renders" do
      assert {:ok, result} = DotPrompt.render("roleplay_leadership", %{}, %{})
      assert is_binary(result.prompt)
    end

    test "roleplay_patient renders" do
      assert {:ok, result} = DotPrompt.render("roleplay_patient", %{}, %{})
      assert is_binary(result.prompt)
    end
  end

  describe "utility prompts" do
    test "qa_response renders with context" do
      params = %{context: "NLP is about communication patterns"}
      assert {:ok, result} = DotPrompt.render("qa_response", params, %{})
      assert result.prompt =~ "NLP"
    end

    test "analysis_agent renders" do
      assert {:ok, result} = DotPrompt.render("analysis_agent", %{}, %{})
      assert is_binary(result.prompt)
    end
  end
end
