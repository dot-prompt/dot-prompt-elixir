defmodule DotPrompt.VersionMajorTest do
  use ExUnit.Case, async: false

  alias DotPrompt.Parser.{Lexer, Parser}

  describe "major version derivation from @version field in init block" do
    test "derives major from integer @version" do
      content = """
      init do
        @version: 2
      end init

      Test prompt.
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
      # In AST, it's just a map of metadata
      assert ast.init.def.version == 2

      # We need to test the extraction logic used in DotPrompt
      # Since major_from_version is private, we'll verify it via DotPrompt.compile
      assert {:ok, result} = DotPrompt.compile(content, %{})
      assert result.major == 2
      assert result.version == 2
    end

    test "derives major from float-like @version string" do
      content = """
      init do
        @version: 2.3
      end init

      Test prompt.
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
      assert ast.init.def.version == "2.3"

      assert {:ok, result} = DotPrompt.compile(content, %{})
      assert result.major == 2
      assert result.version == "2.3"
    end

    test "handles 'v' prefix in @version" do
      content = """
      init do
        @version: v3.1.2
      end init

      Test prompt.
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
      assert ast.init.def.version == "v3.1.2"

      assert {:ok, result} = DotPrompt.compile(content, %{})
      assert result.major == 3
      assert result.version == "v3.1.2"
    end

    test "defaults to major: 1 when not specified" do
      content = """
      init do
        # no version
      end init

      Test prompt.
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, _ast} = Parser.parse(tokens)

      assert {:ok, result} = DotPrompt.compile(content, %{})
      assert result.major == 1
      assert result.version == 1
    end

    test "@major is no longer special and doesn't override major derivation" do
      content = """
      init do
        @major: 5
        @version: 2.1
      end init

      Test prompt.
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
      # @major is now just another parameter/metadata field
      assert ast.init.params["@major"].type == "5"
      assert ast.init.def.version == "2.1"

      assert {:ok, result} = DotPrompt.compile(content, %{})
      # Should be 2, not 5
      assert result.major == 2
      assert result.version == "2.1"
    end
  end
end
