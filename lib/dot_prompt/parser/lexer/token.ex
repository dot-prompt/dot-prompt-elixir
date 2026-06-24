defmodule DotPrompt.Parser.Lexer.Token do
  @moduledoc """
  Represents a single token from the lexer.
  """
  defstruct [:type, :value, :line, :meta, :indent]
end
