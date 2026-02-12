defmodule Clawdex.Tool.Write do
  @moduledoc false

  @behaviour Clawdex.Tool.Behaviour

  @impl true
  def name, do: "write"

  @impl true
  def description, do: "Write or create a file. Creates parent directories if needed."

  @impl true
  def parameters_schema do
    %{
      "type" => "object",
      "properties" => %{
        "path" => %{"type" => "string", "description" => "File path relative to workspace"},
        "content" => %{"type" => "string", "description" => "Content to write"}
      },
      "required" => ["path", "content"]
    }
  end

  @impl true
  def execute(%{"path" => path, "content" => content}, context) do
    workspace = Map.fetch!(context, :workspace)

    case resolve_path(path, workspace) do
      {:ok, full_path} ->
        write_file(full_path, content)

      {:error, reason} ->
        {:ok, %{output: "", error: reason, exit_code: 1}}
    end
  end

  defp resolve_path(path, workspace) do
    full_path = Path.expand(path, workspace)

    if String.starts_with?(full_path, Path.expand(workspace)) do
      {:ok, full_path}
    else
      {:error, "Path traversal denied: #{path}"}
    end
  end

  defp write_file(path, content) do
    path |> Path.dirname() |> File.mkdir_p!()

    case File.write(path, content) do
      :ok ->
        {:ok, %{output: "File written: #{path}", error: nil, exit_code: 0}}

      {:error, reason} ->
        {:ok, %{output: "", error: "Failed to write file: #{inspect(reason)}", exit_code: 1}}
    end
  end
end
