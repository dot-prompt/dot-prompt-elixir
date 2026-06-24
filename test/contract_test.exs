defmodule DotPrompt.ContractTest do
  use ExUnit.Case, async: false

  alias DotPrompt.Parser.{Lexer, Parser}

  describe "response block collection and schema derivation" do
    test "parses response block in if branch" do
      content = """
      init do
        @version: 1
        @is_question: bool
      end init

      if @is_question is true do
        Answer directly.
        response do
          {"response_type": "question", "content": "string"}
        end response
      end @is_question
      """

      assert {:ok, %DotPrompt.Result{prompt: result}} =
               DotPrompt.compile(content, %{is_question: true})

      assert is_binary(result)
    end

    test "parses response block in case branch" do
      content = """
      init do
        @version: 1
        @mode: enum[teaching, question]
      end init

      case @mode do
        teaching: Teach the concept.
        response do
          {"response_type": "teaching", "content": "string"}
        end response

        question: Answer the question.
        response do
          {"response_type": "question", "content": "string"}
        end response
      end @mode
      """

      assert {:ok, %DotPrompt.Result{prompt: result}} =
               DotPrompt.compile(content, %{mode: "teaching"})

      assert is_binary(result)
    end
  end

  describe "ResponseCollector module" do
    alias DotPrompt.Compiler.ResponseCollector

    test "collects response blocks from AST" do
      content = """
      init do
        @version: 1
      end init

      response do
        {"name": "string"}
      end response
      """

      tokens = Lexer.tokenize(content)
      {:ok, ast} = Parser.parse(tokens)

      blocks = ResponseCollector.collect_response_blocks(ast.body)
      assert length(blocks) == 1
      {content, _line} = Enum.at(blocks, 0)
      assert content =~ "name"
    end

    test "derives schema from JSON with actual values" do
      json = ~s({"name": "Alice", "count": 42, "active": true})
      schema = ResponseCollector.derive_schema(json)

      name_schema = Map.get(schema["properties"], "name")
      assert name_schema["type"] == "string"
      assert Map.get(schema["properties"], "count")["type"] == "integer"
      assert Map.get(schema["properties"], "active")["type"] == "boolean"
    end

    test "compares identical schemas" do
      schemas = [
        %{"name" => %{type: "string", required: true}},
        %{"name" => %{type: "string", required: true}}
      ]

      assert ResponseCollector.compare_schemas(schemas) == :identical
    end

    test "compares schemas with different default values" do
      schemas = [
        %{
          "name" => %{type: "string", required: true},
          "value" => %{type: "number", required: true, default: 42}
        },
        %{
          "name" => %{type: "string", required: true},
          "value" => %{type: "number", required: true, default: 100}
        }
      ]

      assert ResponseCollector.compare_schemas(schemas) == :compatible
    end

    test "compares schemas with different fields" do
      schemas = [
        %{"name" => %{type: "string", required: true}},
        %{
          "name" => %{type: "string", required: true},
          "extra" => %{type: "number", required: true}
        }
      ]

      assert ResponseCollector.compare_schemas(schemas) == :incompatible
    end
  end
end
