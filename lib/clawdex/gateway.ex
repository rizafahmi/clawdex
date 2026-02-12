defmodule Clawdex.Gateway do
  @moduledoc false

  require Logger

  alias Clawdex.Config.Loader
  alias Clawdex.LLM.Resolver
  alias Clawdex.Session
  alias Clawdex.Session.{Message, SessionRegistry}
  alias Clawdex.Tool.Registry, as: ToolRegistry

  @max_tool_iterations 10

  @spec send_text(String.t(), String.t()) :: :ok
  def send_text(session_key, text) do
    config = Loader.get()
    {:ok, _pid} = SessionRegistry.get_or_start(session_key)

    user_msg = Message.new(:user, text)
    :ok = Session.append(session_key, user_msg)

    run_agent_loop(session_key, config, 0)
    :ok
  end

  @spec subscribe(String.t()) :: :ok
  def subscribe(session_key) do
    Phoenix.PubSub.subscribe(Clawdex.PubSub, "gateway:session:#{session_key}")
  end

  defp run_agent_loop(session_key, _config, iteration) when iteration >= @max_tool_iterations do
    finish(session_key, "Max tool iterations reached.")
  end

  defp run_agent_loop(session_key, config, iteration) do
    history =
      session_key
      |> Session.get_history()
      |> Enum.map(&Message.to_api_format/1)

    model = Session.get_model(session_key) || config.agent.model
    tool_policy = tool_policy(config)
    tool_schemas = ToolRegistry.schemas(tool_policy)

    case resolve_and_chat(model, config, history, tool_schemas) do
      {:ok, {:tool_use, tool_calls, text_parts}} ->
        maybe_broadcast_text(session_key, text_parts)
        handle_tool_calls(session_key, config, tool_calls, text_parts, iteration)

      {:ok, {:text, reply_text}} ->
        finish(session_key, reply_text)

      {:ok, text} when is_binary(text) ->
        finish(session_key, text)

      {:error, reason} ->
        Logger.error("LLM error in gateway: #{inspect(reason)}")
        broadcast(session_key, %{type: "error", content: error_message(reason)})
        broadcast(session_key, %{type: "done"})
    end
  end

  defp handle_tool_calls(session_key, config, tool_calls, text_parts, iteration) do
    workspace = get_workspace(config)

    assistant_content = build_assistant_content(tool_calls, text_parts)
    assistant_msg = Message.new(:assistant, Jason.encode!(assistant_content))
    Session.append(session_key, assistant_msg)

    Enum.each(tool_calls, fn call ->
      broadcast(session_key, %{type: "tool_use", tool_name: call.name, input: call.input})

      result = execute_tool(call, workspace)

      broadcast(session_key, %{type: "tool_result", tool_name: call.name, output: result.output})

      tool_result_msg =
        Message.new(
          :user,
          Jason.encode!(%{
            type: "tool_result",
            tool_use_id: call.id,
            content: result.output
          })
        )

      Session.append(session_key, tool_result_msg)
    end)

    run_agent_loop(session_key, config, iteration + 1)
  end

  defp execute_tool(call, workspace) do
    context = %{workspace: workspace}

    case ToolRegistry.get(call.name) do
      {:ok, tool_module} ->
        case tool_module.execute(call.input, context) do
          {:ok, result} ->
            result

          {:error, reason} ->
            %{output: "Tool error: #{inspect(reason)}", error: inspect(reason), exit_code: 1}
        end

      :not_found ->
        %{output: "Unknown tool: #{call.name}", error: "not_found", exit_code: 1}
    end
  end

  defp finish(session_key, text) do
    msg = Message.new(:assistant, text)
    Session.append(session_key, msg)
    broadcast(session_key, %{type: "text", content: text})
    broadcast(session_key, %{type: "done"})
  end

  defp maybe_broadcast_text(_session_key, ""), do: :ok
  defp maybe_broadcast_text(_session_key, nil), do: :ok

  defp maybe_broadcast_text(session_key, text),
    do: broadcast(session_key, %{type: "text", content: text})

  defp build_assistant_content(tool_calls, text_parts) do
    text_part =
      if text_parts && text_parts != "", do: [%{type: "text", text: text_parts}], else: []

    tool_parts =
      Enum.map(tool_calls, fn call ->
        %{type: "tool_use", id: call.id, name: call.name, input: call.input}
      end)

    text_part ++ tool_parts
  end

  defp broadcast(session_key, event) do
    Phoenix.PubSub.broadcast(
      Clawdex.PubSub,
      "gateway:session:#{session_key}",
      {:chat_event, Map.put(event, :session_key, session_key)}
    )
  end

  defp get_workspace(config) do
    case config do
      %{agent: %{workspace: ws}} when is_binary(ws) and ws != "" -> Path.expand(ws)
      _ -> Path.expand("~/.clawdex/workspace")
    end
  end

  defp tool_policy(config) do
    config.agent.tools
  end

  defp resolve_and_chat(model, config, history, _tool_schemas) do
    case Resolver.resolve(model, config) do
      {:ok, {module, _model_id, opts}} ->
        opts = Keyword.put_new(opts, :system, config.agent.system_prompt)
        module.chat(history, opts)

      {:error, _} = error ->
        error
    end
  end

  defp error_message(:invalid_api_key), do: "API key invalid. Check config."
  defp error_message(:rate_limited), do: "Rate limited, try again shortly."
  defp error_message(:timeout), do: "Request timed out."
  defp error_message(:unknown_provider), do: "Unknown model provider. Check model name."
  defp error_message(_), do: "Something went wrong. Please try again."
end
