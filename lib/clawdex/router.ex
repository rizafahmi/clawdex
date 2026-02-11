defmodule Clawdex.Router do
  @moduledoc false

  require Logger

  alias Clawdex.Config.Loader
  alias Clawdex.Session
  alias Clawdex.Session.{Message, SessionRegistry}

  @spec handle_inbound(map()) :: :ok
  def handle_inbound(%{text: "/" <> _ = text} = message) do
    handle_command(text, message)
  end

  def handle_inbound(message) do
    Task.start(fn -> process_message(message) end)
    :ok
  end

  defp handle_command("/reset" <> _, message) do
    session_key = session_key(message)

    case SessionRegistry.lookup(session_key) do
      {:ok, _pid} ->
        Session.reset(session_key)
        send_reply(message, "Session reset.")

      :not_found ->
        send_reply(message, "Session reset.")
    end

    :ok
  end

  defp handle_command("/status" <> _, message) do
    session_key = session_key(message)
    config = Loader.get()

    status =
      case SessionRegistry.lookup(session_key) do
        {:ok, _pid} ->
          info = Session.get_info(session_key)

          """
          Model: #{config.agent.model}
          Messages: #{info.message_count}
          Session started: #{info.created_at}
          """

        :not_found ->
          """
          Model: #{config.agent.model}
          Messages: 0
          No active session.
          """
      end

    send_reply(message, String.trim(status))
    :ok
  end

  defp handle_command(_text, message) do
    Task.start(fn -> process_message(message) end)
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

    opts = [
      api_key: config.gemini.api_key,
      model: config.agent.model,
      system: config.agent.system_prompt
    ]

    case llm_module().chat(history, opts) do
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

      {:error, reason} ->
        Logger.error("LLM error: #{inspect(reason)}")
        send_reply(message, "Something went wrong. Please try again.")
    end
  end

  defp session_key(%{channel: channel, chat_id: chat_id}) do
    "#{channel}:#{chat_id}"
  end

  defp send_reply(%{channel: :telegram, chat_id: chat_id}, text) do
    channel_module().send_reply(chat_id, text)
  end

  defp llm_module do
    Application.get_env(:clawdex, :llm_module, Clawdex.LLM.Gemini)
  end

  defp channel_module do
    Application.get_env(:clawdex, :channel_module, Clawdex.Channel.Telegram)
  end
end
