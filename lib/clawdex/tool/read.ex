defmodule Clawdex.Tool.Read do
  @moduledoc false

  @behaviour Clawdex.Tool.Behaviour

  @impl true
  def name, do: "read"

  @impl true
  def description, do: "Read a file's contents. Supports optional line range."

  @impl true
  def parameters_schema do
    %{
      "type" => "object",
      "properties" => %{
        "path" => %{"type" => "string", "description" => "File path relative to workspace"},
        "start_line" => %{
          "type" => "integer",
          "description" => "Start line (1-indexed, optional)"
        },
        "end_line" => %{"type" => "integer", "description" => "End line (1-indexed, optional)"}
      },
      "required" => ["path"]
    }
  end

  @impl true
  def execute(%{"path" => path} = params, context) do
    workspace = Map.fetch!(context, :workspace)

    case resolve_path(path, workspace) do
      {:ok, full_path} ->
        read_file(full_path, params)

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

  defp read_file(path, params) do
    case File.read(path) do
      {:ok, content} ->
        lines = String.split(content, "\n")
        start_line = Map.get(params, "start_line", 1) |> max(1)
        end_line = Map.get(params, "end_line", length(lines))

        output =
          lines
          |> Enum.with_index(1)
          |> Enum.filter(fn {_line, idx} -> idx >= start_line and idx <= end_line end)
          |> Enum.map_join("\n", fn {line, idx} -> "#{idx}: #{line}" end)

        {:ok, %{output: output, error: nil, exit_code: 0}}

      {:error, :enoent} ->
        {:ok, %{output: "", error: "File not found: #{path}", exit_code: 1}}

      {:error, reason} ->
        {:ok, %{output: "", error: "Failed to read file: #{inspect(reason)}", exit_code: 1}}
    end
  end
end
