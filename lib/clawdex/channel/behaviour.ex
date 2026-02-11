defmodule Clawdex.Channel.Behaviour do
  @moduledoc false

  @callback send_reply(chat_id :: term(), text :: String.t()) :: :ok | {:error, term()}
end
