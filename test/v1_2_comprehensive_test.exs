defmodule DotPrompt.V12ComprehensiveTest do
  use ExUnit.Case, async: false

  @prompts_dir Path.expand("test/fixtures/v1_2_test", File.cwd!())

  setup do
    original_dir = Application.get_env(:anantha_dot_prompt, :prompts_dir)
    Application.put_env(:anantha_dot_prompt, :prompts_dir, @prompts_dir)
    File.mkdir_p!(Path.join(@prompts_dir, "archive"))
    File.mkdir_p!(Path.join([@prompts_dir, "skills", "archive"]))

    # Current version (v2) - major derived from version 2.1
    File.write!(Path.join(@prompts_dir, "demo.prompt"), """
    init do
      @version: 2.1
      params:
        @name: str
    end init
    V2: Hello @name
    """)

    # Archived version (v1)
    File.write!(Path.join([@prompts_dir, "archive", "demo_v1.prompt"]), """
    init do
      @version: 1.0
      params:
        @user: str
    end init
    V1: Hello @user
    """)

    # Nested fragment current (v2)
    File.write!(Path.join([@prompts_dir, "skills", "model.prompt"]), """
    init do
      @version: 2.1
    end init
    V2 Model
    """)

    # Nested fragment archived (v1) - version 1.1, major derived as 1
    File.write!(Path.join([@prompts_dir, "skills", "archive", "model_v1.prompt"]), """
    init do
      @version: 1.1
    end init
    V1 Model
    """)

    on_exit(fn ->
      Application.put_env(:anantha_dot_prompt, :prompts_dir, original_dir)
      File.rm_rf!(@prompts_dir)
    end)

    :ok
  end

  describe "Major Version Resolution & Archiving" do
    test "resolves current version by default" do
      assert {:ok, result} = DotPrompt.render("demo", %{name: "Alice"}, %{})
      assert result.prompt =~ "V2: Hello Alice"
      assert result.major == 2
      assert result.version == "2.1"
    end

    test "resolves archived version when major pinned" do
      assert {:ok, result} = DotPrompt.render("demo", %{user: "Bob"}, %{}, major: 1)
      assert result.prompt =~ "V1: Hello Bob"
      assert result.major == 1
      assert result.version == "1.0"
    end

    test "resolves current version when major matches" do
      assert {:ok, result} = DotPrompt.render("demo", %{name: "Charlie"}, %{}, major: 2)
      assert result.prompt =~ "V2: Hello Charlie"
      assert result.major == 2
    end

    test "fails if requested major not found" do
      assert_raise RuntimeError, ~r/prompt_not_found/, fn ->
        DotPrompt.compile("demo", %{}, major: 3)
      end
    end

    test "resolves nested archived fragments" do
      assert {:ok, result} = DotPrompt.compile("skills/model", %{}, major: 1)
      assert result.prompt =~ "V1 Model"
      assert result.major == 1
    end

    test "schema/2 respects major version" do
      assert {:ok, schema1} = DotPrompt.schema("demo", 1)
      assert schema1.major == 1
      assert Map.has_key?(schema1.params, "user")

      assert {:ok, schema2} = DotPrompt.schema("demo", 2)
      assert schema2.major == 2
      assert Map.has_key?(schema2.params, "name")
    end
  end

  describe "Response Contracts (v1.2)" do
    test "collects and derive schema from multiple response blocks" do
      content = """
      if @expert do
        response do
          { "level": "expert", "score": 100 }
        end response
      else
        response do
          { "level": "beginner", "score": 10 }
        end response
      end if
      """

      assert {:ok, result} = DotPrompt.compile(content, %{expert: true})
      # Both blocks have level (str) and score (int)
      assert result.response_contract["type"] == "object"
      assert result.response_contract["properties"]["level"]["type"] == "string"
      assert result.response_contract["properties"]["score"]["type"] == "integer"
    end

    test "returns error for incompatible contracts" do
      content = """
      if @a do
        response do
          { "id": 1 }
        end response
      else
        response do
          { "id": "one" }
        end response
      end if
      """

      assert {:error, %{error: "validation_error", message: msg}} =
               DotPrompt.compile(content, %{a: true})

      assert msg =~ "incompatible_contracts"
    end

    test "identifies compatible contracts (different fields)" do
      content = """
      if @a do
        response do
          { "status": 1 }
        end response
      else
        response do
          { "status": 2, "extra": true }
        end response
      end if
      """

      # This should be incompatible currently because of different keys
      assert {:error, %{error: "validation_error", message: msg}} =
               DotPrompt.compile(content, %{a: true})

      assert msg =~ "incompatible_contracts"
    end

    test "injects {response_contract} placeholder" do
      content = """
      Instructions:
      {response_contract}

      response do
        { "ok": true }
      end response
      """

      assert {:ok, result} = DotPrompt.compile(content, %{})
      assert result.prompt =~ "Instructions:"
      assert result.prompt =~ "\"ok\""
      assert result.prompt =~ "true"
      # Verify it's injected as JSON with object type
      assert result.prompt =~ "\"type\": \"object\""
    end
  end

  describe "DotPrompt.Result struct validation" do
    test "contains all required fields" do
      content = "hello\n"
      assert {:ok, %DotPrompt.Result{} = result} = DotPrompt.compile(content, %{})

      assert Map.has_key?(result, :prompt)
      assert Map.has_key?(result, :response_contract)
      assert Map.has_key?(result, :vary_selections)
      assert Map.has_key?(result, :compiled_tokens)
      assert Map.has_key?(result, :cache_hit)
      assert Map.has_key?(result, :major)
      assert Map.has_key?(result, :version)
      assert Map.has_key?(result, :metadata)
    end
  end
end
