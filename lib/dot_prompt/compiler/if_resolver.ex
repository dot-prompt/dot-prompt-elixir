defmodule DotPrompt.Compiler.IfResolver do
  @moduledoc """
  Resolves if/elif/else conditions using natural language operators.
  """

  @type condition_type ::
          {:is, any()}
          | {:not, any()}
          | {:includes, any()}
          | {:above, integer()}
          | {:below, integer()}
          | {:min, integer()}
          | {:max, integer()}
          | {:between, integer(), integer()}

  @doc """
  Resolves a condition string against a value.
  """
  def resolve(var_value, condition_str) do
    condition_str
    |> String.trim()
    |> parse_condition()
    |> evaluate(var_value)
  end

  defp parse_condition("is " <> rest), do: {:is, parse_value(rest)}
  defp parse_condition("not " <> rest), do: {:not, parse_value(rest)}
  defp parse_condition("includes " <> rest), do: {:includes, parse_value(rest)}
  defp parse_condition("above " <> rest), do: {:above, safe_to_integer(rest)}
  defp parse_condition("below " <> rest), do: {:below, safe_to_integer(rest)}
  defp parse_condition("min " <> rest), do: {:min, safe_to_integer(rest)}
  defp parse_condition("max " <> rest), do: {:max, safe_to_integer(rest)}

  defp parse_condition("between " <> rest) do
    case String.split(rest, " and ", parts: 2) do
      [x, y] -> {:between, safe_to_integer(x), safe_to_integer(y)}
      _ -> {:is, rest}
    end
  end

  defp parse_condition(other), do: {:is, parse_value(other)}

  defp evaluate({:is, expected}, val), do: compare(val, expected) == :eq
  defp evaluate({:not, expected}, val), do: compare(val, expected) != :eq

  defp evaluate({:includes, expected}, val) when is_list(val) do
    Enum.any?(val, fn v -> compare(v, expected) == :eq end)
  end

  defp evaluate({:includes, _}, _), do: false

  defp evaluate({:above, expected}, val) when is_number(expected) do
    v = to_int(val)
    is_number(v) and v > expected
  end

  defp evaluate({:below, expected}, val) when is_number(expected) do
    v = to_int(val)
    is_number(v) and v < expected
  end

  defp evaluate({:min, expected}, val) when is_number(expected) do
    v = to_int(val)
    is_number(v) and v >= expected
  end

  defp evaluate({:max, expected}, val) when is_number(expected) do
    v = to_int(val)
    is_number(v) and v <= expected
  end

  defp evaluate({:between, x, y}, val) when is_number(x) and is_number(y) do
    v = to_int(val)
    is_number(v) and v >= x and v <= y
  end

  defp evaluate(_, _), do: false

  defp compare(a, b) when a === b, do: :eq

  defp compare(a, b) do
    if to_string(a) == to_string(b), do: :eq, else: :neq
  end

  defp to_int(v) when is_integer(v), do: v

  defp to_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {num, ""} -> num
      _ -> nil
    end
  end

  defp to_int(_), do: nil

  defp safe_to_integer(val) do
    case Integer.parse(String.trim(to_string(val))) do
      {num, ""} -> num
      _ -> nil
    end
  end

  defp parse_value("true"), do: true
  defp parse_value("false"), do: false
  defp parse_value("nil"), do: nil

  defp parse_value(val) do
    case Integer.parse(val) do
      {num, ""} -> num
      _ -> val
    end
  end
end
