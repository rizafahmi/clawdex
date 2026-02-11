defmodule Clawdex.Channel.Telegram do
  @moduledoc false

  use GenServer

  require Logger

  @behaviour Clawdex.Channel.Behaviour

  @base_url "https://api.telegram.org/bot"
  @poll_timeout 30

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Clawdex.Channel.Behaviour
  def send_reply(chat_id, text) do
    token = Clawdex.Config.Loader.get().channels.telegram.bot_token

    case api_request(token, "sendMessage", %{chat_id: chat_id, text: text}) do
      {:ok, %{"message_id" => message_id}} -> {:ok, message_id}
      {:ok, _} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Clawdex.Channel.Behaviour
  def edit_reply(chat_id, message_id, text) do
    token = Clawdex.Config.Loader.get().channels.telegram.bot_token

    case api_request(token, "editMessageText", %{
           chat_id: chat_id,
           message_id: message_id,
           text: text
         }) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl GenServer
  def init(_opts) do
    config = Clawdex.Config.Loader.get()
    token = config.channels.telegram.bot_token
    send(self(), :poll)
    {:ok, %{token: token, offset: 0}}
  end

  @impl GenServer
  def handle_info(:poll, state) do
    {updates, new_offset} = fetch_updates(state.token, state.offset)

    for update <- updates do
      handle_update(update)
    end

    send(self(), :poll)
    {:noreply, %{state | offset: new_offset}}
  end

  defp fetch_updates(token, offset) do
    params = %{offset: offset, timeout: @poll_timeout, allowed_updates: ["message"]}

    case api_request(token, "getUpdates", params) do
      {:ok, updates} when is_list(updates) ->
        new_offset =
          case List.last(updates) do
            %{"update_id" => id} -> id + 1
            _ -> offset
          end

        {updates, new_offset}

      {:error, reason} ->
        Logger.warning("Telegram poll error: #{inspect(reason)}")
        Process.sleep(5_000)
        {[], offset}
    end
  end

  defp handle_update(%{"message" => %{"text" => text, "chat" => chat, "from" => from}}) do
    message = %{
      channel: :telegram,
      chat_id: chat["id"],
      sender_id: from["id"],
      sender_name: from["first_name"],
      text: text,
      timestamp: DateTime.utc_now()
    }

    Clawdex.Router.handle_inbound(message)
  end

  defp handle_update(_), do: :ok

  defp api_request(token, method, params) do
    url = "#{@base_url}#{token}/#{method}"

    case Req.post(url, json: params, receive_timeout: (@poll_timeout + 5) * 1_000) do
      {:ok, %Req.Response{status: 200, body: %{"ok" => true, "result" => result}}} ->
        {:ok, result}

      {:ok, %Req.Response{body: %{"description" => desc}}} ->
        {:error, desc}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
