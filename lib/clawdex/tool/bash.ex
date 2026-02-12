defmodule Clawdex.Tool.Bash do
  @moduledoc false

  @behaviour Clawdex.Tool.Behaviour

  @max_output_bytes 10_240
  @default_timeout 60_000

  @impl true
  def name, do: "bash"

  @impl true
  def description, do: "Execute a shell command in the workspace directory."

  @impl true
  def parameters_schema do
    %{
      "type" => "object",
      "properties" => %{
        "command" => %{"type" => "string", "description" => "Shell command to execute"}
      },
      "required" => ["command"]
    }
  end

  @impl true
  def execute(%{"command" => command}, context) do
    workspace = Map.fetch!(context, :workspace)
    timeout = Map.get(context, :timeout, @default_timeout)

    port =
      Port.open({:spawn, command}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:cd, workspace}
      ])

    collect_output(port, <<>>, timeout)
  end

  defp collect_output(port, output, timeout) do
    receive do
      {^port, {:data, data}} ->
        new_output = output <> data

        if byte_size(new_output) > @max_output_bytes do
          Port.close(port)
          truncated = binary_part(new_output, 0, @max_output_bytes)

          {:ok,
           %{
             output: truncated <> "\n[output truncated at #{@max_output_bytes} bytes]",
             error: nil,
             exit_code: nil
           }}
        else
          collect_output(port, new_output, timeout)
        end

      {^port, {:exit_status, status}} ->
        {:ok, %{output: output, error: nil, exit_code: status}}
    after
      timeout ->
        Port.close(port)
        {:ok, %{output: output, error: "Command timed out after #{timeout}ms", exit_code: nil}}
    end
  end
end
