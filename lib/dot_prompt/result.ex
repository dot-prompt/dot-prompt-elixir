defmodule DotPrompt.Result do
  @moduledoc """
  Result struct returned from compile/render operations.
  """
  defstruct prompt: nil,
            response_contract: nil,
            vary_selections: %{},
            compiled_tokens: 0,
            injected_tokens: 0,
            cache_hit: false,
            major: nil,
            version: nil,
            metadata: %{},
            system: nil,
            user: nil

  @type t :: %DotPrompt.Result{
          prompt: String.t() | nil,
          response_contract: map() | nil,
          vary_selections: map() | nil,
          compiled_tokens: integer(),
          injected_tokens: integer(),
          cache_hit: boolean(),
          major: integer() | nil,
          version: String.t() | integer() | nil,
          metadata: map() | nil,
          system: String.t() | nil,
          user: String.t() | nil
        }
end
