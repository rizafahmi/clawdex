defmodule Clawdex.Tool.EditTest do
  use ExUnit.Case, async: true

  alias Clawdex.Tool.Edit

  @workspace Path.expand("test/fixtures/edit_workspace")

  setup do
    File.rm_rf!(@workspace)
    File.mkdir_p!(@workspace)
    File.write!(Path.join(@workspace, "code.py"), "print('hello')\nprint('world')\n")
    on_exit(fn -> File.rm_rf!(@workspace) end)
    %{context: %{workspace: @workspace}}
  end

  test "replaces a unique string", %{context: ctx} do
    {:ok, result} =
      Edit.execute(
        %{"path" => "code.py", "old_str" => "print('hello')", "new_str" => "print('goodbye')"},
        ctx
      )

    assert result.exit_code == 0
    content = File.read!(Path.join(@workspace, "code.py"))
    assert content =~ "print('goodbye')"
    refute content =~ "print('hello')"
  end

  test "fails when old_str matches multiple locations", %{context: ctx} do
    File.write!(Path.join(@workspace, "dup.py"), "print('a')\nprint('a')\n")

    {:ok, result} =
      Edit.execute(
        %{"path" => "dup.py", "old_str" => "print('a')", "new_str" => "print('b')"},
        ctx
      )

    assert result.exit_code == 1
    assert result.error =~ "matches 2 locations"
  end

  test "fails when old_str not found", %{context: ctx} do
    {:ok, result} =
      Edit.execute(
        %{"path" => "code.py", "old_str" => "nonexistent", "new_str" => "replacement"},
        ctx
      )

    assert result.exit_code == 1
    assert result.error =~ "not found"
  end

  test "rejects path traversal", %{context: ctx} do
    {:ok, result} =
      Edit.execute(
        %{"path" => "../../evil.py", "old_str" => "x", "new_str" => "y"},
        ctx
      )

    assert result.exit_code == 1
    assert result.error =~ "Path traversal denied"
  end

  test "handles file not found", %{context: ctx} do
    {:ok, result} =
      Edit.execute(
        %{"path" => "missing.py", "old_str" => "x", "new_str" => "y"},
        ctx
      )

    assert result.exit_code == 1
    assert result.error =~ "File not found"
  end

  test "name returns edit" do
    assert Edit.name() == "edit"
  end
end
