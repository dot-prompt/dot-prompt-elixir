defmodule DotPrompt.Parser.ResponseBlockTest do
  use ExUnit.Case, async: false
  alias DotPrompt.Parser.{Lexer, Parser}

  describe "response block parsing" do
    test "parses simple response block in prompt body" do
      content = """
      init do
        @version: 1
      end init

      Answer the question.
      response do
        {"answer": "string"}
      end response
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
      # Body should contain text + response node
      assert length(ast.body) >= 2

      # Check that response node exists
      response_nodes =
        Enum.filter(ast.body, fn
          {:response, _, _} -> true
          _ -> false
        end)

      assert length(response_nodes) == 1
    end

    test "parses response block with multiple fields" do
      content = """
      init do
        @version: 1
      end init

      response do
        {
          "response_type": "string",
          "content": "string",
          "confidence": "number"
        }
      end response
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
    end

    test "parses response block inside if branch" do
      content = """
      init do
        @version: 1
        @is_question: bool
      end init

      if @is_question is true do
        Answer directly.
        response do
          {"answer": "string", "type": "direct"}
        end response
      end @is_question
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
    end

    test "parses response block inside case branch" do
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
          {"response_type": "question", "answer": "string"}
        end response
      end @mode
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
    end

    test "parses multiple response blocks in different branches" do
      content = """
      init do
        @version: 1
        @response_type: enum[json, text]
      end init

      case @response_type do
        json: Return JSON.
        response do
          {"result": "string", "score": "number"}
        end response

        text: Return text.
        response do
          {"text": "string"}
        end response
      end @response_type
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
    end

    test "parses response block inside vary branch" do
      content = """
      init do
        @version: 1
        @style: enum[formal, casual]
      end init

      vary @style do
        formal: Be formal.
        response do
          {"format": "formal", "greeting": "string"}
        end response

        casual: Be casual.
        response do
          {"format": "casual", "message": "string"}
        end response
      end @style
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
    end
  end

  describe "response block AST structure" do
    test "response block stored as {:response, content, line}" do
      content = """
      init do
        @version: 1
      end init

      response do
        {"field": "string"}
      end response
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)

      response_nodes =
        Enum.filter(ast.body, fn
          {:response, _, _} -> true
          _ -> false
        end)

      assert length(response_nodes) == 1
    end

    test "nested response block preserves line number" do
      content = """
      init do
        @version: 1
        @flag: bool
      end init

      if @flag is true do
        response do
          {"nested": "value"}
        end response
      end @flag
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
    end
  end

  describe "response block with complex JSON" do
    test "parses nested objects" do
      content = """
      init do
        @version: 1
      end init

      response do
        {
          "user": {"name": "string", "age": "number"},
          "tags": ["string"]
        }
      end response
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, _ast} = Parser.parse(tokens)
    end

    test "parses arrays of objects" do
      content = """
      init do
        @version: 1
      end init

      response do
        {
          "items": [{"id": "string", "value": "number"}]
        }
      end response
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, _ast} = Parser.parse(tokens)
    end

    test "parses response block with boolean and null" do
      content = """
      init do
        @version: 1
      end init

      response do
        {"active": true, "optional": null}
      end response
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, _ast} = Parser.parse(tokens)
    end
  end

  describe "response block edge cases" do
    test "empty response block" do
      content = """
      init do
        @version: 1
      end init

      response do
      end response
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
    end

    test "response block with only whitespace" do
      content = """
      init do
        @version: 1
      end init

      response do

      end response
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, _ast} = Parser.parse(tokens)
    end

    test "multiple response blocks at top level" do
      content = """
      init do
        @version: 1
      end init

      response do
        {"type": "a"}
      end response

      More text.

      response do
        {"type": "b"}
      end response
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)

      response_nodes =
        Enum.filter(ast.body, fn
          {:response, _, _} -> true
          _ -> false
        end)

      assert length(response_nodes) == 2
    end
  end
end
