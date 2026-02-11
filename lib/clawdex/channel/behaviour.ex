defmodule Clawdex.Channel.Behaviour do
  @moduledoc false

  @callback send_reply(chat_id :: term(), text :: String.t()) ::
              {:ok, message_id :: term()} | {:error, term()}

  @callback edit_reply(chat_id :: term(), message_id :: term(), text :: String.t()) ::
              :ok | {:error, term()}
end
