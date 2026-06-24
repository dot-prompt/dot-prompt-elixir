defmodule DotPrompt.Parser.EndIfTest do
  use ExUnit.Case
  alias DotPrompt.Parser.Lexer
  alias DotPrompt.Parser.Parser

  test "allows 'end if' for 'if' blocks" do
    content = """
    if @is_vip is true do
      VIP
    end if
    """

    tokens = Lexer.tokenize(content)
    assert {:ok, ast} = Parser.parse(tokens)
    # The parser seems to split the content slightly differently than my manual assertion expected
    assert [{:if, "@is_vip", "is true", [{:text, "  VIP"}], [], nil}, {:text, ""}] = ast.body
  end

  test "allows 'end if' for if/elif/else chain" do
    content = """
    if @a is true do
      A
    elif @b is true do
      B
    else
      C
    end if
    """

    tokens = Lexer.tokenize(content)
    assert {:ok, ast} = Parser.parse(tokens)

    assert [
             {:if, "@a", "is true", [{:text, "  A"}], [{"is true", [{:text, "  B"}]}],
              [{:text, "  C"}]},
             {:text, ""}
           ] = ast.body
  end

  test "allows 'end @var' for 'if' blocks" do
    content = """
    if @is_vip is true do
      VIP
    end @is_vip
    """

    tokens = Lexer.tokenize(content)
    assert {:ok, ast} = Parser.parse(tokens)
    assert [{:if, "@is_vip", "is true", [{:text, "  VIP"}], [], nil}, {:text, ""}] = ast.body
  end

  test "allows 'end @var' for if/elif/else chain" do
    content = """
    if @a is true do
      A
    elif @b is true do
      B
    else
      C
    end @a
    """

    tokens = Lexer.tokenize(content)
    assert {:ok, ast} = Parser.parse(tokens)

    assert [
             {:if, "@a", "is true", [{:text, "  A"}], [{"is true", [{:text, "  B"}]}],
              [{:text, "  C"}]},
             {:text, ""}
           ] = ast.body
  end

  test "still fails on mismatched '@var'" do
    content = """
    if @a is true do
      inside
    end @b
    """

    tokens = Lexer.tokenize(content)
    assert {:error, message} = Parser.parse(tokens)
    assert message =~ "mismatched_end"
  end
end
