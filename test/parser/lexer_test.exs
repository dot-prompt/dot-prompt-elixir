defmodule DotPrompt.Parser.LexerTest do
  use ExUnit.Case, async: false
  alias DotPrompt.Parser.Lexer

  test "tokenizes all control flow keywords" do
    content = """
    init do
    docs do
    if @var is x do
    elif @var is y do
    else
    case @var do
    vary @intro_style do
    end @var
    end init
    end docs
    end @intro_style
    """

    tokens = Lexer.tokenize(content)

    types = Enum.map(tokens, & &1.type)
    assert :block_start in types
    assert :condition in types
    assert :else in types
    assert :case_start in types
    assert :vary_start in types
    assert :block_end in types
  end

  test "tokenizes sigils and comments" do
    content = """
    # This is a comment
    @var: int[1..5] -> docs
    {static_frag}: static
    {{dynamic_frag}}: dynamic
    Text with @var and {{runtime_var}}
    """

    tokens = Lexer.tokenize(content)

    refute Enum.any?(tokens, fn t -> t.type == :text and String.contains?(t.value, "#") end)

    assert Enum.any?(tokens, fn t ->
             t.type == :param_def and t.value == "@var" and
               String.contains?(t.meta, "int[1..5]")
           end)

    assert Enum.any?(tokens, fn t ->
             t.type == :fragment_def and t.value == "{static_frag}" and t.meta == "static"
           end)

    assert Enum.any?(tokens, fn t ->
             t.type == :fragment_def and t.value == "{{dynamic_frag}}" and t.meta == "dynamic"
           end)

    assert Enum.any?(tokens, fn t ->
             t.type == :text and String.contains?(t.value, "Text with @var")
           end)
  end

  test "tokenizes defaults with =" do
    content = "@depth: enum[shallow, medium, deep] = medium -> doc"
    tokens = Lexer.tokenize(content)

    assert Enum.any?(tokens, fn t ->
             t.type == :param_def and t.value == "@depth" and
               String.contains?(t.meta, "enum[shallow, medium, deep] = medium")
           end)

    assert Enum.any?(tokens, fn t -> t.type == :doc and t.value == "doc" end)
  end

  test "handles empty lines and whitespace" do
    content = "\n  \n  if @var is x do  \n\n  end @var  \n"
    tokens = Lexer.tokenize(content)

    assert Enum.any?(tokens, &(&1.type == :text and String.trim(&1.value) == ""))
    assert Enum.any?(tokens, &(&1.type == :condition))
  end

  describe "message sections" do
    test "tokenizes system do block" do
      content = """
      init do
      end init
      system do
      You are a helpful assistant.
      end system
      """

      tokens = Lexer.tokenize(content)
      types = Enum.map(tokens, & &1.type)

      assert :block_start in types
      assert Enum.any?(tokens, fn t -> t.type == :block_start and t.value == "system" end)
      assert Enum.any?(tokens, fn t -> t.type == :block_end and t.value == "system" end)
    end

    test "tokenizes user do block" do
      content = """
      init do
      end init
      user do
      What is the weather?
      end user
      """

      tokens = Lexer.tokenize(content)
      types = Enum.map(tokens, & &1.type)

      assert :block_start in types
      assert Enum.any?(tokens, fn t -> t.type == :block_start and t.value == "user" end)
      assert Enum.any?(tokens, fn t -> t.type == :block_end and t.value == "user" end)
    end

    test "tokenizes context do block" do
      content = """
      init do
      end init
      context do
      Previous conversation history here.
      end context
      """

      tokens = Lexer.tokenize(content)
      types = Enum.map(tokens, & &1.type)

      assert :block_start in types
      assert Enum.any?(tokens, fn t -> t.type == :block_start and t.value == "context" end)
      assert Enum.any?(tokens, fn t -> t.type == :block_end and t.value == "context" end)
    end

    test "tokenizes multiple message sections" do
      content = """
      init do
      end init
      system do
      You are an AI assistant.
      end system
      user do
      Hello
      end user
      context do
      Previous messages.
      end context
      """

      tokens = Lexer.tokenize(content)

      assert Enum.any?(tokens, fn t -> t.type == :block_start and t.value == "system" end)
      assert Enum.any?(tokens, fn t -> t.type == :block_start and t.value == "user" end)
      assert Enum.any?(tokens, fn t -> t.type == :block_start and t.value == "context" end)
      assert Enum.any?(tokens, fn t -> t.type == :block_end and t.value == "system" end)
      assert Enum.any?(tokens, fn t -> t.type == :block_end and t.value == "user" end)
      assert Enum.any?(tokens, fn t -> t.type == :block_end and t.value == "context" end)
    end
  end

  describe "role field" do
    test "tokenizes role init item" do
      content = """
      init do
      role: system
      end init
      """

      tokens = Lexer.tokenize(content)

      assert Enum.any?(tokens, fn t ->
               t.type == :init_item and t.value == "role" and t.meta == "system"
             end)
    end

    test "tokenizes role with description" do
      content = """
      init do
      role: assistant -> The role this prompt represents
      end init
      """

      tokens = Lexer.tokenize(content)

      assert Enum.any?(tokens, fn t ->
               t.type == :init_item and t.value == "role" and t.meta == "assistant"
             end)

      assert Enum.any?(tokens, fn t ->
               t.type == :doc and t.value == "The role this prompt represents"
             end)
    end
  end
end
