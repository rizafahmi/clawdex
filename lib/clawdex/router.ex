defmodule Clawdex.Router do
  @moduledoc false

  require Logger

  alias Clawdex.Config.Loader
  alias Clawdex.LLM.Resolver
  alias Clawdex.Session
  alias Clawdex.Session.{Message, SessionRegistry}

  @spec handle_inbound(map()) :: :ok
  def handle_inbound(%{text: "/" <> _ = text} = message) do
    handle_command(text, message)
  end

  def handle_inbound(message) do
    Task.Supervisor.start_child(Clawdex.TaskSupervisor, fn -> process_message(message) end)
    :ok
  end

  defp handle_command("/reset" <> _, message) do
    with_session(message, fn session_key, _pid ->
      Session.reset(session_key)
      send_reply(message, "Session reset.")
    end, fn _ ->
      send_reply(message, "Session reset.")
    end)
  end

  defp handle_command("/status" <> _, message) do
    config = Loader.get()

    with_session(message, fn session_key, _pid ->
      info = Session.get_info(session_key)
      model = info.model_override || config.agent.model

      status = """
      Model: #{model}
      Messages: #{info.message_count}
      Session started: #{info.created_at}
      """
      send_reply(message, String.trim(status))
    end, fn _ ->
      status = """
      Model: #{config.agent.model}
      Messages: 0
      No active session.
      """
      send_reply(message, String.trim(status))
    end)
  end

  defp handle_command("/model" <> rest, message) do
    case String.trim(rest) do
      "" -> show_current_model(message)
      model_name -> switch_model(message, model_name)
    end
  end

  defp handle_command("/compact" <> _, message) do
    with_session(message, fn session_key, _pid ->
      case Session.get_history(session_key) do
        [_, _, _, _ | _] = history ->
          Task.Supervisor.start_child(Clawdex.TaskSupervisor, fn ->
            do_compact(session_key, history, message)
          end)

        _ ->
          send_reply(message, "Not enough messages to compact.")
      end
    end, fn _ ->
      send_reply(message, "No active session to compact.")
    end)
  end

  defp handle_command("/help" <> _, message) do
    help_text = """
    Available commands:
    /reset — Clear session history
    /status — Show model, message count, session age
    /model <name> — Switch model (e.g., /model openai/gpt-4o)
    /model — Show current model
    /compact — Summarize old messages to free context window
    /help — Show this help message
    """

    send_reply(message, String.trim(help_text))
    :ok
  end

  defp handle_command(_text, message) do
    Task.Supervisor.start_child(Clawdex.TaskSupervisor, fn -> process_message(message) end)
    :ok
  end

  defp show_current_model(message) do
    config = Loader.get()

    with_session(message, fn session_key, _pid ->
      current = Session.get_model(session_key) || config.agent.model
      send_reply(message, "Current model: #{current}")
    end, fn _ ->
      send_reply(message, "Current model: #{config.agent.model}")
    end)
  end

  defp switch_model(message, model_name) do
    session_key = session_key(message)
    {:ok, _pid} = SessionRegistry.get_or_start(session_key)
    Session.set_model(session_key, model_name)
    send_reply(message, "Model switched to: #{model_name}")
    :ok
  end

  defp process_message(message) do
    session_key = session_key(message)
    config = Loader.get()

    {:ok, _pid} = SessionRegistry.get_or_start(session_key)

    user_msg = Message.new(:user, message.text)
    :ok = Session.append(session_key, user_msg)

    history =
      session_key
      |> Session.get_history()
      |> Enum.map(&Message.to_api_format/1)

    model = Session.get_model(session_key) || config.agent.model

    case resolve_and_chat(model, config, history) do
      {:ok, reply_text} ->
        assistant_msg = Message.new(:assistant, reply_text)
        :ok = Session.append(session_key, assistant_msg)
        send_reply(message, reply_text)

      {:error, :invalid_api_key} ->
        send_reply(message, "API key invalid. Check config.")

      {:error, :rate_limited} ->
        send_reply(message, "Rate limited, try again shortly.")

      {:error, :timeout} ->
        send_reply(message, "Request timed out.")

      {:error, :unknown_provider} ->
        send_reply(message, "Unknown model provider. Check model name.")

      {:error, reason} ->
        Logger.error("LLM error: #{inspect(reason)}")
        send_reply(message, "Something went wrong. Please try again.")
    end
  end

  defp resolve_and_chat(model, config, history) do
    case Resolver.resolve(model, config) do
      {:ok, {module, _model_id, opts}} ->
        opts = Keyword.put_new(opts, :system, config.agent.system_prompt)
        module.chat(history, opts)

      {:error, _} = error ->
        error
    end
  end

  defp do_compact(session_key, history, message) do
    config = Loader.get()
    split_at = div(length(history), 2)
    {to_summarize, to_keep} = Enum.split(history, split_at)

    summary_prompt =
      Enum.map(to_summarize, &Message.to_api_format/1) ++
        [%{"role" => "user", "content" => "Summarize the conversation above in a concise paragraph."}]

    model = Session.get_model(session_key) || config.agent.model

    case resolve_and_chat(model, config, summary_prompt) do
      {:ok, summary_text} ->
        Session.reset(session_key)
        summary_msg = Message.new(:assistant, "[Compacted summary] " <> summary_text)
        Session.append(session_key, summary_msg)

        Enum.each(to_keep, &Session.append(session_key, &1))

        send_reply(message, "Compacted #{split_at} messages into a summary.")

      {:error, _reason} ->
        send_reply(message, "Failed to compact. Try again later.")
    end
  end

  defp with_session(message, success_fun, not_found_fun) do
    session_key = session_key(message)

    case SessionRegistry.lookup(session_key) do
      {:ok, pid} -> success_fun.(session_key, pid)
      :not_found -> not_found_fun.(session_key)
    end
    :ok
  end

  defp session_key(%{channel: channel, chat_id: chat_id}) do
    "#{channel}:#{chat_id}"
  end

  defp send_reply(%{channel: :telegram, chat_id: chat_id}, text) do
    channel_module().send_reply(chat_id, text)
  end

  defp channel_module do
    Application.get_env(:clawdex, :channel_module, Clawdex.Channel.Telegram)
  end
end
