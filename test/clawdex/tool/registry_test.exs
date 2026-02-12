defmodule Clawdex.Tool.RegistryTest do
  use ExUnit.Case, async: true

  alias Clawdex.Tool.Registry

  test "list returns all tools" do
    tools = Registry.list()
    assert length(tools) == 4
    names = Enum.map(tools, & &1.name())
    assert "bash" in names
    assert "read" in names
    assert "write" in names
    assert "edit" in names
  end

  test "list with allow policy filters tools" do
    tools = Registry.list(%{allow: ["read", "write"]})
    names = Enum.map(tools, & &1.name())
    assert "read" in names
    assert "write" in names
    refute "bash" in names
  end

  test "list with deny policy excludes tools" do
    tools = Registry.list(%{deny: ["bash"]})
    names = Enum.map(tools, & &1.name())
    refute "bash" in names
    assert "read" in names
  end

  test "get finds a tool by name" do
    assert {:ok, Clawdex.Tool.Bash} = Registry.get("bash")
    assert {:ok, Clawdex.Tool.Read} = Registry.get("read")
  end

  test "get returns :not_found for unknown tool" do
    assert :not_found = Registry.get("unknown")
  end

  test "schemas returns JSON schema array" do
    schemas = Registry.schemas()
    assert length(schemas) == 4
    assert Enum.all?(schemas, fn s -> is_binary(s["name"]) end)
    assert Enum.all?(schemas, fn s -> is_binary(s["description"]) end)
    assert Enum.all?(schemas, fn s -> is_map(s["input_schema"]) end)
  end

  test "schemas respects policy" do
    schemas = Registry.schemas(%{allow: ["read"]})
    assert length(schemas) == 1
    assert hd(schemas)["name"] == "read"
  end
end
