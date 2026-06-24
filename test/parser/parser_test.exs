defmodule DotPrompt.Parser.ParserTest do
  use ExUnit.Case, async: false
  alias DotPrompt.Parser.{Lexer, Parser}

  setup_all do
    original_dir = Application.get_env(:anantha_dot_prompt, :prompts_dir)
    prompts_dir = Path.expand("test/fixtures/prompts", File.cwd!())
    Application.put_env(:anantha_dot_prompt, :prompts_dir, prompts_dir)

    on_exit(fn ->
      Application.put_env(:anantha_dot_prompt, :prompts_dir, original_dir)
    end)

    :ok
  end

  describe "init block parsing" do
    test "parses @version as metadata" do
      content = """
      init do
        @version: 2
      end init
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
      assert ast.init.def.version == 2
    end

    test "parses multiline docs and indented continuations" do
      content = """
      init do
        params:
          @user: str = "Alice"
            -> The user name
               Must be unique
      end init
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
      assert ast.init.params["@user"].doc =~ "The user name"
      assert ast.init.params["@user"].doc =~ "Must be unique"
    end

    test "parses init block with def: section" do
      content = """
      init do
        @version: 1
        def:
          mode: fragment
          description: Test prompt
      end init
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
      assert ast.init.def.version == 1
      assert ast.init.def.mode == "fragment"
      assert ast.init.def.description == "Test prompt"
    end

    test "parses init block at start of prompt" do
      content = """
      init do
        @version: 1
      end init

      This is the prompt body.
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
      assert ast.init.params["@version"] != nil
      assert ast.body != []
    end

    test "parses init block with params: section" do
      content = """
      init do
        params:
          @user: str
            -> The user name
      end init
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
      # params: is stored in def
      assert ast.init.def[:params] == ""
      # @user: str is stored in params with string key
      assert ast.init.params["@user"] != nil
    end

    test "parses init block with fragments: section" do
      content = """
      init do
        fragments:
          {my_fragment}: static from: skills
      end init
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
      # fragments: stored in def
      assert ast.init.def[:fragments] == ""
      # fragment definition stored in fragments (braces stripped from key)
      assert ast.init.fragments["my_fragment"] != nil
    end

    test "parses init block with docs: block" do
      content = """
      init do
        docs do
          This is the documentation.
          It has multiple lines.
        end docs
      end init
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
      assert ast.init.docs =~ "documentation"
      assert ast.init.docs =~ "multiple lines"
    end

    test "parses empty init block" do
      content = """
      init do
      end init
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
      assert ast.init != nil
      assert ast.init.def == %{}
    end

    test "returns error on unclosed init block" do
      content = """
      init do
        @version: 1
      """

      tokens = Lexer.tokenize(content)
      assert {:error, message} = Parser.parse(tokens)
      assert message =~ "EOF" or message =~ "Unexpected"
    end

    test "parses complex init block with all sections" do
      content = """
      init do
        @version: 1

        def:
          mode: fragment

        params:
          @input: str
            -> The input text

        fragments:
          {greeting}: static

        docs do
          Documentation for the prompt.
        end docs
      end init

      Prompt body starts here.
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
      assert ast.init.params["@version"] != nil
      # def: and params: section labels are stored in def
      assert ast.init.def[:def] == ""
      assert ast.init.def[:params] == ""
      assert ast.init.params["@input"] != nil
      assert ast.init.fragments["greeting"] != nil
      assert ast.init.docs =~ "Documentation"
    end

    test "parses init block with section labels (def:, params:, fragments:)" do
      content = """
      init do
        def:
          mode: fragment
        params:
          @user: str
        fragments:
          {myfrag}: static
      end init
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
      # Section labels stored as init_item
      assert ast.init.def[:def] == ""
      assert ast.init.def[:params] == ""
      assert ast.init.def[:fragments] == ""
      # Variables stored in params
      assert ast.init.params["@user"] != nil
      # Fragments stored in fragments (braces stripped from key)
      assert ast.init.fragments["myfrag"] != nil
    end

    test "parses init block with docstrings on variables" do
      content = """
      init do
        @name: str
          -> The user's name
        @age: int
          -> The user's age in years
      end init
      """

      tokens = Lexer.tokenize(content)
      assert {:ok, ast} = Parser.parse(tokens)
      assert ast.init.params["@name"] != nil
      # The doc field includes the docstring
      assert ast.init.params["@name"].doc =~ "user's name"
      assert ast.init.params["@age"] != nil
      assert ast.init.params["@age"].doc =~ "age in years"
    end
  end

  test "returns error on mismatched end" do
    content = """
    if @var is x do
    end @wrong_var
    """

    tokens = Lexer.tokenize(content)
    assert {:error, message} = Parser.parse(tokens)
    assert message =~ "mismatched_end" or message =~ "Unexpected"
  end

  test "returns error on unclosed block" do
    content = "if @var is x do"
    tokens = Lexer.tokenize(content)
    assert {:error, message} = Parser.parse(tokens)
    assert message =~ "unclosed_block"
  end
end
