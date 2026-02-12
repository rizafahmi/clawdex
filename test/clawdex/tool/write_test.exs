defmodule Clawdex.Tool.WriteTest do
  use ExUnit.Case, async: true

  alias Clawdex.Tool.Write

  @workspace Path.expand("test/fixtures/write_workspace")

  setup do
    File.rm_rf!(@workspace)
    File.mkdir_p!(@workspace)
    on_exit(fn -> File.rm_rf!(@workspace) end)
    %{context: %{workspace: @workspace}}
  end

  test "writes a new file", %{context: ctx} do
    {:ok, result} = Write.execute(%{"path" => "new.txt", "content" => "hello\n"}, ctx)
    assert result.exit_code == 0
    assert File.read!(Path.join(@workspace, "new.txt")) == "hello\n"
  end

  test "creates parent directories", %{context: ctx} do
    {:ok, result} = Write.execute(%{"path" => "sub/dir/file.txt", "content" => "nested\n"}, ctx)
    assert result.exit_code == 0
    assert File.read!(Path.join(@workspace, "sub/dir/file.txt")) == "nested\n"
  end

  test "rejects path traversal", %{context: ctx} do
    {:ok, result} = Write.execute(%{"path" => "../../evil.txt", "content" => "bad"}, ctx)
    assert result.exit_code == 1
    assert result.error =~ "Path traversal denied"
  end

  test "name returns write" do
    assert Write.name() == "write"
  end
end
