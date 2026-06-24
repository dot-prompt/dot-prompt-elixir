defmodule DotPrompt.InjectorTest do
  use ExUnit.Case, async: true
  alias DotPrompt.Injector

  test "injects runtime variables" do
    template = "Hello {{user_name}}, welcome to {{project}}."
    runtime = %{user_name: "Alice", project: "dot-prompt"}

    result = Injector.inject(template, runtime)
    assert result == "Hello Alice, welcome to dot-prompt."
  end

  test "injects using both @ and {{}} sigils" do
    template = "Message: @user_message (by {{user_name}})"
    runtime = %{user_message: "Hello world", user_name: "Alice"}

    result = Injector.inject(template, runtime)
    assert result == "Message: Hello world (by Alice)"
  end

  test "handles numeric and boolean runtime values" do
    template = "Score: {{score}}, Active: {{is_active}}"
    runtime = %{score: 100, is_active: true}

    result = Injector.inject(template, runtime)
    assert result == "Score: 100, Active: true"
  end
end
