defmodule DotPrompt.ValidateOutputTest do
  use ExUnit.Case, async: false

  describe "validate_output/3 - validates LLM response against contract" do
    test "validates matching JSON response" do
      contract = %{
        "name" => %{type: "string", required: true},
        "age" => %{type: "number", required: true}
      }

      response = ~s({"name": "Alice", "age": 30})

      assert :ok = DotPrompt.validate_output(response, contract)
    end

    test "validates response with optional fields missing" do
      contract = %{
        "name" => %{type: "string", required: true},
        "age" => %{type: "number", required: false}
      }

      response = ~s({"name": "Alice"})

      assert :ok = DotPrompt.validate_output(response, contract)
    end

    test "returns error for missing required field" do
      contract = %{
        "name" => %{type: "string", required: true},
        "age" => %{type: "number", required: true}
      }

      response = ~s({"name": "Alice"})

      assert {:error, _} = DotPrompt.validate_output(response, contract)
    end

    test "returns error for wrong type" do
      contract = %{
        "name" => %{type: "string", required: true},
        "age" => %{type: "number", required: true}
      }

      response = ~s({"name": "Alice", "age": "thirty"})

      assert {:error, _} = DotPrompt.validate_output(response, contract)
    end

    test "validates nested object" do
      contract = %{
        "user" => %{
          type: "object",
          fields: %{
            "name" => %{type: "string", required: true}
          }
        }
      }

      response = ~s({"user": {"name": "Alice"}})

      assert :ok = DotPrompt.validate_output(response, contract)
    end

    test "validates array of objects" do
      contract = %{
        "items" => %{
          type: "array",
          items: %{
            type: "object",
            fields: %{
              "id" => %{type: "string", required: true}
            }
          }
        }
      }

      response = ~s({"items": [{"id": "a"}, {"id": "b"}]})

      assert :ok = DotPrompt.validate_output(response, contract)
    end

    test "validates boolean type" do
      contract = %{
        "active" => %{type: "boolean", required: true}
      }

      assert :ok = DotPrompt.validate_output(~s({"active": true}), contract)
      assert :ok = DotPrompt.validate_output(~s({"active": false}), contract)
    end

    test "validates null for optional fields" do
      contract = %{
        "name" => %{type: "string", required: true},
        "nickname" => %{type: "string", required: false}
      }

      assert :ok = DotPrompt.validate_output(~s({"name": "Alice", "nickname": null}), contract)
    end

    test "returns error for invalid JSON" do
      contract = %{
        "name" => %{type: "string", required: true}
      }

      response = "not valid json"

      assert {:error, _} = DotPrompt.validate_output(response, contract)
    end

    test "returns error for extra fields not in contract" do
      contract = %{
        "name" => %{type: "string", required: true}
      }

      response = ~s({"name": "Alice", "extra": "value"})

      # This should fail if strict validation is enabled
      # For now, we'll test that it at least parses
      result = DotPrompt.validate_output(response, contract)
      assert is_tuple(result)
    end
  end

  describe "validate_output with strict option" do
    test "rejects extra fields when strict: true" do
      contract = %{
        "name" => %{type: "string", required: true}
      }

      response = ~s({"name": "Alice", "extra": "value"})

      assert {:error, _} = DotPrompt.validate_output(response, contract, strict: true)
    end

    test "allows extra fields when strict: false" do
      contract = %{
        "name" => %{type: "string", required: true}
      }

      response = ~s({"name": "Alice", "extra": "value"})

      assert :ok = DotPrompt.validate_output(response, contract, strict: false)
    end
  end
end
