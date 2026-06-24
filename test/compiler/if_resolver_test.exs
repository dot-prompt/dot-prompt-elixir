defmodule DotPrompt.Compiler.IfResolverTest do
  use ExUnit.Case, async: false
  alias DotPrompt.Compiler.IfResolver

  test "resolves equality (is)" do
    assert IfResolver.resolve(true, "is true")
    assert IfResolver.resolve(false, "is false")
    assert IfResolver.resolve("advanced", "is advanced")
    assert IfResolver.resolve(10, "is 10")
  end

  test "resolves inequality (not)" do
    assert IfResolver.resolve("beginner", "not advanced")
    refute IfResolver.resolve("advanced", "not advanced")
    assert IfResolver.resolve(5, "not 10")
  end

  test "resolves numeric comparisons" do
    assert IfResolver.resolve(10, "above 5")
    refute IfResolver.resolve(5, "above 10")

    assert IfResolver.resolve(5, "below 10")
    refute IfResolver.resolve(10, "below 5")

    assert IfResolver.resolve(10, "min 10")
    assert IfResolver.resolve(11, "min 10")

    assert IfResolver.resolve(10, "max 10")
    assert IfResolver.resolve(9, "max 10")
  end

  test "resolves inclusive range (between x and y)" do
    assert IfResolver.resolve(3, "between 1 and 5")
    assert IfResolver.resolve(1, "between 1 and 5")
    assert IfResolver.resolve(5, "between 1 and 5")
    refute IfResolver.resolve(0, "between 1 and 5")
    refute IfResolver.resolve(6, "between 1 and 5")
  end

  test "handles string and numeric types appropriately" do
    assert IfResolver.resolve("10", "is 10")
    assert IfResolver.resolve(10, "is 10")
  end
end
