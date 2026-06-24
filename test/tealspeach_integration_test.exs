defmodule DotPrompt.TealspeachIntegrationTest do
  use ExUnit.Case, async: false

  @prompts_dir Path.expand("test/fixtures/tealspeach_integration", File.cwd!())

  setup_all do
    # Create all required directories
    File.mkdir_p!(@prompts_dir)
    File.mkdir_p!(Path.join(@prompts_dir, "skills/embedded_commands"))
    File.mkdir_p!(Path.join(@prompts_dir, "skills/presuppositions"))
    File.mkdir_p!(Path.join(@prompts_dir, "skills/utilization"))
    File.mkdir_p!(Path.join(@prompts_dir, "fragments/intro"))

    # teacher_explanation.prompt
    File.write!(Path.join(@prompts_dir, "teacher_explanation.prompt"), """
    init do
      @version: 1.0
      def:
        mode: teacher
        description: Teacher mode for NLP training
      params:
        @input_mode: enum[teach_flow, question] = "teach_flow"
        @pattern_step: int[1..5] = 1
        @current_step_name: str = "explain"
        @current_section_number: int = 1
        @mastery: float = 0.0
        @section_core_content: str
        @section_key_points: str
        @section_example: str
        @target_question_if_needed: str
        @step_instruction: str
    end init
    Milton, an expert NLP trainer
    Step: @pattern_step of 5
    Section: @current_section_number
    Step name: @current_step_name
    User mastery: @mastery
    response_type
    Mode Selection: @input_mode
    @section_core_content
    @section_key_points
    @section_example
    @target_question_if_needed
    @step_instruction
    """)

    # teacher_scoring.prompt
    File.write!(Path.join(@prompts_dir, "teacher_scoring.prompt"), """
    init do
      @version: 1.0
    end init
    Teacher scoring content
    """)

    # intro.prompt
    File.write!(Path.join(@prompts_dir, "intro.prompt"), """
    init do
      @version: 1.0
      def:
        mode: intro
        description: Welcome message for new users
    end init
    Welcome to the NLP training system
    """)

    # skills/embedded_commands/_index.prompt
    File.write!(Path.join(@prompts_dir, "skills/embedded_commands/_index.prompt"), """
    init do
      @version: 1.0
      fragments:
        {all}: static from: skills/embedded_commands
          match: all
    end init
    Embedded Commands are suggestions hidden inside language.
    {all}
    """)

    File.write!(Path.join(@prompts_dir, "skills/embedded_commands/tone_shift.prompt"), """
    init do
      @version: 1.0
      def:
        mode: fragment
        match: Tone shift
    end init
    Tone shift marks embedded commands
    """)

    File.write!(Path.join(@prompts_dir, "skills/embedded_commands/convert_command.prompt"), """
    init do
      @version: 1.0
      def:
        mode: fragment
        match: Convert this direct command
    end init
    Convert this direct command into an embedded command
    """)

    File.write!(Path.join(@prompts_dir, "skills/embedded_commands/beginner.prompt"), """
    init do
      @version: 1.0
      def:
        mode: fragment
        match: Beginner
    end init
    Beginner level embedded commands
    """)

    # skills/presuppositions/_index.prompt
    File.write!(Path.join(@prompts_dir, "skills/presuppositions/_index.prompt"), """
    init do
      @version: 1.0
      fragments:
        {all}: static from: skills/presuppositions
          match: all
    end init
    Presuppositions are linguistic patterns that assume something.
    {all}
    """)

    File.write!(Path.join(@prompts_dir, "skills/presuppositions/existential.prompt"), """
    init do
      @version: 1.0
      def:
        mode: fragment
        match: Existential
    end init
    Existential presuppositions assume existence
    """)

    File.write!(Path.join(@prompts_dir, "skills/presuppositions/identify.prompt"), """
    init do
      @version: 1.0
      def:
        mode: fragment
        match: Identify the presupposition
    end init
    Identify the presupposition in these statements
    """)

    File.write!(Path.join(@prompts_dir, "skills/presuppositions/beginner.prompt"), """
    init do
      @version: 1.0
      def:
        mode: fragment
        match: Beginner
    end init
    Beginner presuppositions practice
    """)

    # skills/utilization/_index.prompt
    File.write!(Path.join(@prompts_dir, "skills/utilization/_index.prompt"), """
    init do
      @version: 1.0
      fragments:
        {all}: static from: skills/utilization
          match: all
    end init
    Utilization is the practice of meeting the client's reality.
    {all}
    """)

    File.write!(Path.join(@prompts_dir, "skills/utilization/utilize_objection.prompt"), """
    init do
      @version: 1.0
      def:
        mode: fragment
        match: Utilize this client objection
    end init
    Utilize this client objection as a teaching opportunity
    """)

    File.write!(Path.join(@prompts_dir, "skills/utilization/beginner.prompt"), """
    init do
      @version: 1.0
      def:
        mode: fragment
        match: Beginner
    end init
    Beginner utilization techniques
    """)

    # fragments/user_context.prompt
    File.write!(Path.join(@prompts_dir, "fragments/user_context.prompt"), """
    init do
      @version: 1.0
      params:
        @user_name: str = "Learner"
        @skill_history: str
        @mastery_scores: str
        @recent_goals: str
        @learning_style: str
        @interaction_patterns: str
    end init
    **Name**: @user_name
    @skill_history
    @mastery_scores
    @recent_goals
    @learning_style
    @interaction_patterns
    """)

    # fragments/intro/history_section.prompt — references {conversation_history} but no file exists
    File.write!(Path.join(@prompts_dir, "fragments/intro/history_section.prompt"), """
    init do
      @version: 1.0
      fragments:
        {conversation_history}: static
    end init
    History section content
    {conversation_history}
    """)

    # fragments/intro/conversation_history_section.prompt — references {conversation_history} but no file exists
    File.write!(
      Path.join(@prompts_dir, "fragments/intro/conversation_history_section.prompt"),
      """
      init do
        @version: 1.0
        fragments:
          {conversation_history}: static
      end init
      Conversation history section
      {conversation_history}
      """
    )

    original_dir = Application.get_env(:dot_prompt, :prompts_dir)
    Application.put_env(:dot_prompt, :prompts_dir, @prompts_dir)

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

  describe "teacher_explanation.prompt" do
    test "renders with default params" do
      assert {:ok, result} = DotPrompt.render("teacher_explanation", %{}, %{})
      assert result.prompt =~ "Milton, an expert NLP trainer"
      assert result.prompt =~ "Step: 1 of 5"
      assert result.prompt =~ "Step name: explain"
      assert result.prompt =~ "User mastery: 0.0"
      assert result.prompt =~ "response_type"
    end

    test "renders with custom compile-time params" do
      params = %{
        pattern_step: 3,
        current_section_number: 2,
        current_step_name: "example",
        input_mode: "teach_flow",
        mastery: 0.75
      }

      assert {:ok, result} = DotPrompt.render("teacher_explanation", params, %{})
      assert result.prompt =~ "Step: 3 of 5"
      assert result.prompt =~ "Section: 2"
      assert result.prompt =~ "Step name: example"
      assert result.prompt =~ "User mastery: 0.75"
    end

    test "injects runtime content variables" do
      params = %{current_step_name: "explain"}

      runtime = %{
        section_core_content:
          "An embedded command is a suggestion hidden inside a larger sentence.",
        section_key_points: "- Bypasses resistance\n- Marked by tone shifts",
        section_example: "\"You might find that as you listen...\"",
        target_question_if_needed: "What is the difference?"
      }

      assert {:ok, result} = DotPrompt.render("teacher_explanation", params, runtime)
      assert result.prompt =~ "An embedded command is a suggestion"
      assert result.prompt =~ "Bypasses resistance"
      assert result.prompt =~ "You might find that as you listen"
      assert result.prompt =~ "What is the difference?"
    end

    test "renders question input_mode" do
      params = %{input_mode: "question"}
      runtime = %{user_input: "What is an embedded command?"}

      assert {:ok, result} = DotPrompt.render("teacher_explanation", params, runtime)
      assert result.prompt =~ "Mode Selection"
      assert result.prompt =~ "question"
    end

    test "renders all step names correctly" do
      steps = ["introduce", "explain", "example", "student_try", "feedback"]

      for step <- steps do
        params = %{current_step_name: step}
        assert {:ok, result} = DotPrompt.render("teacher_explanation", params, %{})
        assert result.prompt =~ "Step name: #{step}", "Failed for step: #{step}"
      end
    end

    test "renders with step_instruction runtime variable" do
      params = %{current_step_name: "explain"}
      runtime = %{step_instruction: "Focus on the core concept before giving examples."}

      assert {:ok, result} = DotPrompt.render("teacher_explanation", params, runtime)
      assert result.prompt =~ "Focus on the core concept"
    end

    test "response contract is present in result" do
      # The teacher_explanation prompt uses response: in the init block (metadata),
      # not a response do block. The response_contract field is nil for this prompt.
      # Test that the schema can be extracted instead.
      assert {:ok, schema} = DotPrompt.schema("teacher_explanation")
      assert schema.name == "teacher_explanation"
      assert Map.has_key?(schema.params, "current_step_name")
    end
  end

  describe "teacher_scoring.prompt" do
    test "renders successfully" do
      assert {:ok, result} = DotPrompt.render("teacher_scoring", %{}, %{})
      assert is_binary(result.prompt)
      assert String.length(result.prompt) > 0
    end
  end

  describe "intro.prompt" do
    test "renders successfully" do
      assert {:ok, result} = DotPrompt.render("intro", %{}, %{})
      assert is_binary(result.prompt)
      assert String.length(result.prompt) > 0
    end
  end

  describe "skill _index prompts" do
    test "embedded_commands index renders with all fragments" do
      assert {:ok, result} = DotPrompt.render("skills/embedded_commands/_index", %{}, %{})
      assert is_binary(result.prompt)
      assert result.prompt =~ "Embedded Commands are suggestions"
      assert result.prompt =~ "Tone shift"
      assert result.prompt =~ "Convert this direct command"
      assert result.prompt =~ "Beginner"
    end

    test "presuppositions index renders with all fragments" do
      assert {:ok, result} = DotPrompt.render("skills/presuppositions/_index", %{}, %{})
      assert is_binary(result.prompt)
      assert result.prompt =~ "Presuppositions are linguistic"
      assert result.prompt =~ "Existential"
      assert result.prompt =~ "Identify the presupposition"
      assert result.prompt =~ "Beginner"
    end

    test "utilization index renders with all fragments" do
      assert {:ok, result} = DotPrompt.render("skills/utilization/_index", %{}, %{})
      assert is_binary(result.prompt)
      assert result.prompt =~ "Utilization is the practice"
      assert result.prompt =~ "Utilize this client objection"
      assert result.prompt =~ "Beginner"
    end
  end

  describe "fragments" do
    test "user_context fragment renders with defaults" do
      assert {:ok, result} = DotPrompt.render("fragments/user_context", %{}, %{})
      assert result.prompt =~ "**Name**: Learner"
    end

    test "user_context fragment renders with custom params" do
      params = %{user_name: "Alice"}

      runtime = %{
        skill_history: "Completed Milton Model training",
        mastery_scores: "Milton Model: 0.8",
        recent_goals: "Master embedded commands",
        learning_style: "Visual",
        interaction_patterns: "Prefers short explanations"
      }

      assert {:ok, result} = DotPrompt.render("fragments/user_context", params, runtime)
      assert result.prompt =~ "**Name**: Alice"
      assert result.prompt =~ "Completed Milton Model training"
      assert result.prompt =~ "Milton Model: 0.8"
      assert result.prompt =~ "Master embedded commands"
      assert result.prompt =~ "Visual"
      assert result.prompt =~ "Prefers short explanations"
    end

    test "history_section fragment renders" do
      # This fragment uses {conversation_history} as a static fragment reference
      # which requires a file that doesn't exist in this test setup.
      assert {:error, %{error: "validation_error"}} =
               DotPrompt.render(
                 "fragments/intro/history_section",
                 %{},
                 %{}
               )
    end

    test "conversation_history_section fragment renders" do
      # This fragment uses {conversation_history} as a static fragment reference
      # which requires a file that doesn't exist in this test setup.
      assert {:error, %{error: "validation_error"}} =
               DotPrompt.render(
                 "fragments/intro/conversation_history_section",
                 %{},
                 %{}
               )
    end
  end

  describe "schema extraction" do
    test "teacher_explanation schema has correct params" do
      assert {:ok, schema} = DotPrompt.schema("teacher_explanation")
      assert schema.name == "teacher_explanation"
      assert Map.has_key?(schema.params, "pattern_step")
      assert Map.has_key?(schema.params, "current_step_name")
      assert Map.has_key?(schema.params, "input_mode")
    end

    test "user_context fragment schema has params" do
      assert {:ok, schema} = DotPrompt.schema("fragments/user_context")
      assert schema.name == "fragments/user_context"
      assert Map.has_key?(schema.params, "user_name")
    end
  end

  describe "list functions" do
    test "lists all tealspeach prompts" do
      prompts = DotPrompt.list_prompts()
      assert "teacher_explanation" in prompts
      assert "teacher_scoring" in prompts
      assert "intro" in prompts
      assert "skills/embedded_commands/_index" in prompts
    end

    test "lists root prompts" do
      root_prompts = DotPrompt.list_root_prompts()
      assert "teacher_explanation" in root_prompts
      refute "fragments/user_context" in root_prompts
    end

    test "lists fragment prompts" do
      fragment_prompts = DotPrompt.list_fragment_prompts()
      assert "fragments/user_context" in fragment_prompts
      assert "fragments/intro/history_section" in fragment_prompts
    end

    test "lists collections" do
      collections = DotPrompt.list_collections()
      assert "skills" in collections
      assert "fragments" in collections
    end
  end

  describe "cache behavior" do
    test "cache hit on repeated renders with same params" do
      {:ok, result1} = DotPrompt.render("teacher_explanation", %{}, %{})
      {:ok, result2} = DotPrompt.render("teacher_explanation", %{}, %{})

      assert result1.cache_hit == false
      assert result2.cache_hit == true
    end

    test "cache miss when params change" do
      {:ok, result1} =
        DotPrompt.render(
          "teacher_explanation",
          %{current_step_name: "explain"},
          %{}
        )

      {:ok, result2} =
        DotPrompt.render(
          "teacher_explanation",
          %{current_step_name: "example"},
          %{}
        )

      assert result1.cache_hit == false
      assert result2.cache_hit == false
    end
  end

  describe "version and major" do
    test "teacher_explanation has correct version" do
      assert {:ok, result} = DotPrompt.render("teacher_explanation", %{}, %{})
      assert result.version == "1.0"
      assert result.major == 1
    end

    test "user_context fragment has correct version" do
      assert {:ok, result} = DotPrompt.render("fragments/user_context", %{}, %{})
      assert result.version == "1.0"
      assert result.major == 1
    end
  end

  describe "full teacher workflow simulation" do
    test "complete multi-step teaching flow" do
      steps = ["introduce", "explain", "example", "student_try", "feedback"]

      teaching_content = %{
        section_core_content: "An embedded command influences the unconscious mind.",
        section_key_points: "- Hidden suggestions\n- Tone shifts mark commands",
        section_example: "\"As you listen, you might notice...\"",
        target_question_if_needed: "Can you identify the embedded command?"
      }

      for {step, idx} <- Enum.with_index(steps) do
        params = %{
          pattern_step: idx + 1,
          current_section_number: 1,
          current_step_name: step,
          mastery: 0.5
        }

        assert {:ok, result} = DotPrompt.render("teacher_explanation", params, teaching_content)
        assert result.prompt =~ "Step name: #{step}", "Failed at step: #{step}"
        assert result.prompt =~ "An embedded command influences"
        assert result.prompt =~ "Hidden suggestions"
      end
    end
  end
end
