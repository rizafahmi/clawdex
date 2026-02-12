defmodule Clawdex.Tool.Edit do
  @moduledoc false

  @behaviour Clawdex.Tool.Behaviour

  @impl true
  def name, do: "edit"

  @impl true
  def description, do: "Replace a string in a file. Fails if old_str matches multiple locations."

  @impl true
  def parameters_schema do
    %{
      "type" => "object",
      "properties" => %{
        "path" => %{"type" => "string", "description" => "File path relative to workspace"},
        "old_str" => %{"type" => "string", "description" => "String to find and replace"},
        "new_str" => %{"type" => "string", "description" => "Replacement string"},
        "start_line" => %{
          "type" => "integer",
          "description" => "Optional start line to narrow search"
        },
        "end_line" => %{
          "type" => "integer",
          "description" => "Optional end line to narrow search"
        }
      },
      "required" => ["path", "old_str", "new_str"]
    }
  end

  @impl true
  def execute(%{"path" => path, "old_str" => old_str, "new_str" => new_str} = params, context) do
    workspace = Map.fetch!(context, :workspace)

    case resolve_path(path, workspace) do
      {:ok, full_path} ->
        do_edit(full_path, old_str, new_str, params)

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

  defp do_edit(path, old_str, new_str, params) do
    case File.read(path) do
      {:ok, content} ->
        target_content = maybe_extract_range(content, params)
        match_count = count_occurrences(target_content, old_str)

        cond do
          match_count == 0 ->
            {:ok, %{output: "", error: "old_str not found in file", exit_code: 1}}

          match_count > 1 ->
            {:ok,
             %{
               output: "",
               error:
                 "old_str matches #{match_count} locations. Provide more context or use start_line/end_line to narrow.",
               exit_code: 1
             }}

          true ->
            apply_and_verify(path, content, old_str, new_str)
        end

      {:error, :enoent} ->
        {:ok, %{output: "", error: "File not found: #{path}", exit_code: 1}}

      {:error, reason} ->
        {:ok, %{output: "", error: "Failed to read file: #{inspect(reason)}", exit_code: 1}}
    end
  end

  defp apply_and_verify(path, content, old_str, new_str) do
    new_content = String.replace(content, old_str, new_str, global: false)
    File.write!(path, new_content)

    verification = File.read!(path)

    if String.contains?(verification, new_str) do
      {:ok, %{output: "Edit applied successfully.", error: nil, exit_code: 0}}
    else
      {:ok, %{output: "", error: "Edit verification failed.", exit_code: 1}}
    end
  end

  defp maybe_extract_range(content, %{"start_line" => start_line, "end_line" => end_line}) do
    content
    |> String.split("\n")
    |> Enum.slice((start_line - 1)..(end_line - 1))
    |> Enum.join("\n")
  end

  defp maybe_extract_range(content, _params), do: content

  defp count_occurrences(content, search) do
    content
    |> String.split(search)
    |> length()
    |> Kernel.-(1)
  end
end
