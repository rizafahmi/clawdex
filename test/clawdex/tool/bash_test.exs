defmodule Clawdex.Tool.BashTest do
  use ExUnit.Case, async: true

  alias Clawdex.Tool.Bash

  @workspace Path.expand("test/fixtures/bash_workspace")

  setup do
    File.rm_rf!(@workspace)
    File.mkdir_p!(@workspace)
    on_exit(fn -> File.rm_rf!(@workspace) end)
    %{context: %{workspace: @workspace}}
  end

  test "executes a simple command", %{context: ctx} do
    {:ok, result} = Bash.execute(%{"command" => "echo hello"}, ctx)
    assert result.exit_code == 0
    assert String.trim(result.output) == "hello"
  end

  test "captures stderr via stderr_to_stdout", %{context: ctx} do
    {:ok, result} = Bash.execute(%{"command" => "echo error >&2"}, ctx)
    assert String.trim(result.output) == "error"
  end

  test "returns exit code for failed commands", %{context: ctx} do
    {:ok, result} = Bash.execute(%{"command" => "/bin/sh -c 'exit 42'"}, ctx)
    assert result.exit_code == 42
  end

  test "runs in workspace directory", %{context: ctx} do
    {:ok, result} = Bash.execute(%{"command" => "pwd"}, ctx)
    assert String.trim(result.output) == @workspace
  end

  test "times out long-running commands", %{context: ctx} do
    ctx = Map.put(ctx, :timeout, 100)
    {:ok, result} = Bash.execute(%{"command" => "sleep 10"}, ctx)
    assert result.error =~ "timed out"
  end

  test "name returns bash" do
    assert Bash.name() == "bash"
  end

  test "parameters_schema returns valid schema" do
    schema = Bash.parameters_schema()
    assert schema["type"] == "object"
    assert "command" in schema["required"]
  end
end
