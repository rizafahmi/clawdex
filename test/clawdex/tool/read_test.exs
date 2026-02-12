defmodule Clawdex.Tool.ReadTest do
  use ExUnit.Case, async: true

  alias Clawdex.Tool.Read

  @workspace Path.expand("test/fixtures/tool_workspace")

  setup do
    File.mkdir_p!(@workspace)
    File.write!(Path.join(@workspace, "hello.txt"), "line1\nline2\nline3\nline4\nline5\n")
    on_exit(fn -> File.rm_rf!(@workspace) end)
    %{context: %{workspace: @workspace}}
  end

  test "reads a file with line numbers", %{context: ctx} do
    {:ok, result} = Read.execute(%{"path" => "hello.txt"}, ctx)
    assert result.exit_code == 0
    assert result.output =~ "1: line1"
    assert result.output =~ "5: line5"
    assert result.error == nil
  end

  test "reads a line range", %{context: ctx} do
    {:ok, result} =
      Read.execute(%{"path" => "hello.txt", "start_line" => 2, "end_line" => 3}, ctx)

    assert result.exit_code == 0
    assert result.output =~ "2: line2"
    assert result.output =~ "3: line3"
    refute result.output =~ "1: line1"
  end

  test "rejects path traversal", %{context: ctx} do
    {:ok, result} = Read.execute(%{"path" => "../../../etc/passwd"}, ctx)
    assert result.exit_code == 1
    assert result.error =~ "Path traversal denied"
  end

  test "returns error for missing file", %{context: ctx} do
    {:ok, result} = Read.execute(%{"path" => "nonexistent.txt"}, ctx)
    assert result.exit_code == 1
    assert result.error =~ "File not found"
  end

  test "name returns read" do
    assert Read.name() == "read"
  end

  test "parameters_schema returns valid schema" do
    schema = Read.parameters_schema()
    assert schema["type"] == "object"
    assert "path" in schema["required"]
  end
end
