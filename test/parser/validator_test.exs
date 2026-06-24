defmodule DotPrompt.Parser.ValidatorTest do
  use ExUnit.Case, async: false
  alias DotPrompt.Parser.Validator
  alias DotPrompt.Parser.Parser
  alias DotPrompt.Parser.Lexer

  describe "validate/1" do
    test "passes for valid AST" do
      content = """
      init do
        params:
          @user: str
      end init
      Hello @user
      """

      tokens = Lexer.tokenize(content)
      {:ok, ast} = Parser.parse(tokens)
      assert {:ok, []} = Validator.validate(ast)
    end

    test "fails for undeclared variables" do
      content = """
      init do
        params:
          @known: str
      end init

      Hello @unknown
      """

      tokens = Lexer.tokenize(content)
      {:ok, ast} = Parser.parse(tokens)

      assert {:error, "unknown_variable: unknown referenced but not declared"} =
               Validator.validate(ast)
    end

    test "fails for deep nesting" do
      content = """
      init do
        params:
          @a: bool
          @b: bool
          @c: bool
          @d: bool
      end init
      if @a is true do
        if @b is true do
          if @c is true do
            if @d is true do
              too deep
            end @d
          end @c
        end @b
      end @a
      """

      tokens = Lexer.tokenize(content)
      {:ok, ast} = Parser.parse(tokens)
      assert {:error, message} = Validator.validate(ast)
      assert message =~ "nesting_exceeded"
    end
  end

  describe "vary block validation" do
    test "fails for unnamed vary block" do
      content = """
      init do
        params:
          @style: enum[a, b]
      end init
      vary do
        a: A
        b: B
      end
      """

      tokens = Lexer.tokenize(content)
      {:ok, ast} = Parser.parse(tokens)
      assert {:error, message} = Validator.validate(ast)
      assert message =~ "invalid_vary"
    end
  end

  describe "validate_params/2" do
    test "validates required compile-time params" do
      declarations = %{"@age" => %{type: :int, lifecycle: :compile, range: [1, 100]}}
      assert :ok = Validator.validate_params(%{age: 25}, declarations)

      assert {:error, "missing_param: @age required but not provided"} =
               Validator.validate_params(%{}, declarations)
    end

    test "validates enum values" do
      declarations = %{"@mode" => %{type: :enum, lifecycle: :compile, values: ["a", "b"]}}

      assert {:error, "invalid_enum: @mode value c not in enum[a, b]"} =
               Validator.validate_params(%{mode: "c"}, declarations)
    end

    test "validates integer ranges" do
      declarations = %{"@age" => %{type: :int, range: [18, 99]}}
      assert :ok = Validator.validate_params(%{age: 25}, declarations)
      assert :ok = Validator.validate_params(%{age: "25"}, declarations)

      assert {:error, "out_of_range: @age value 17 out of range int[18..99]"} =
               Validator.validate_params(%{age: 17}, declarations)
    end

    test "validates boolean types" do
      declarations = %{"@active" => %{type: :bool, lifecycle: :compile}}
      assert :ok = Validator.validate_params(%{active: true}, declarations)

      assert {:error, "invalid_type: @active expected bool, got \"true\""} =
               Validator.validate_params(%{active: "true"}, declarations)
    end

    test "validates list types" do
      declarations = %{"@tags" => %{type: :list, lifecycle: :runtime}}
      assert :ok = Validator.validate_params(%{tags: ["a", "b"]}, declarations)

      assert {:error, "invalid_type: @tags expected list, got \"a\""} =
               Validator.validate_params(%{tags: "a"}, declarations)
    end
  end

  describe "type aliases" do
    test "supports string and boolean aliases" do
      content = """
      init do
        params:
          @s: string
          @b: boolean
      end init
      """

      tokens = Lexer.tokenize(content)
      {:ok, ast} = Parser.parse(tokens)
      decls = Validator.parse_param_declarations_for_schema(ast.init)
      assert decls["@s"].type == :str
      assert decls["@b"].type == :bool
    end
  end

  describe "fragment assembly rules" do
    test "fails when matchRe uses a non-enum variable" do
      content = """
      init do
        params:
          @pattern: str
        fragments:
          {filtered}: static from: skills
            matchRe: @pattern
      end init
      """

      tokens = Lexer.tokenize(content)
      {:ok, ast} = Parser.parse(tokens)
      assert {:error, message} = Validator.validate(ast)
      assert message =~ "invalid_matchre_type"
      assert message =~ "matchRe requires enum variable"
    end

    test "passes when matchRe uses an enum variable" do
      content = """
      init do
        params:
          @pattern: enum[a, b]
        fragments:
          {filtered}: static from: skills
            matchRe: @pattern
      end init
      """

      tokens = Lexer.tokenize(content)
      {:ok, ast} = Parser.parse(tokens)
      assert {:ok, _} = Validator.validate(ast)
    end

    test "supports = for default values" do
      content = """
      init do
        params:
          @depth: enum[shallow, medium, deep] = medium
      end init
      """

      tokens = Lexer.tokenize(content)
      {:ok, ast} = Parser.parse(tokens)
      decls = Validator.parse_param_declarations(ast.init)
      assert decls["@depth"].default == "medium"
    end

    test "fails to find default when using :" do
      content = """
      init do
        params:
          @depth: enum[shallow, medium, deep]: medium
      end init
      """

      tokens = Lexer.tokenize(content)
      {:ok, ast} = Parser.parse(tokens)
      decls = Validator.parse_param_declarations(ast.init)
      # It should treat ": medium" as part of the type string, or at least not as default
      assert decls["@depth"].default == nil
    end

    test "validates list members" do
      content = """
      init do
        params:
          @skills: list[A, B]
      end init
      """

      tokens = Lexer.tokenize(content)
      {:ok, ast} = Parser.parse(tokens)
      decls = Validator.parse_param_declarations(ast.init)

      assert :ok = Validator.validate_params(%{skills: ["A"]}, decls)
      assert :ok = Validator.validate_params(%{skills: ["A", "B"]}, decls)
      assert {:error, msg} = Validator.validate_params(%{skills: ["C"]}, decls)
      assert msg =~ "invalid_enum"
    end
  end
end
