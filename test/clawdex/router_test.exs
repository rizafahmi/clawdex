defmodule Clawdex.RouterTest do
  use ExUnit.Case, async: false

  alias Clawdex.Config.Schema
  alias Clawdex.Router

  @config %Schema{
    agent: %{model: "gemini-3.0-pro-exp", system_prompt: "Be helpful."},
    gemini: %{api_key: "test-key"},
    channels: %{telegram: %{bot_token: "test-token"}}
  }

  setup do
    start_supervised!({Clawdex.Config.Loader, config: @config})

    Clawdex.LLM.Stub.setup()
    Clawdex.Channel.Stub.setup(self())

    Application.put_env(:clawdex, :llm_module, Clawdex.LLM.Stub)
    Application.put_env(:clawdex, :channel_module, Clawdex.Channel.Stub)

    on_exit(fn ->
      Application.delete_env(:clawdex, :llm_module)
      Application.delete_env(:clawdex, :channel_module)
    end)

    :ok
  end

  test "routes a message through LLM and sends reply" do
    Clawdex.LLM.Stub.set_response({:ok, "Hello back!"})

    message = %{
      channel: :telegram,
      chat_id: 123,
      sender_id: 456,
      sender_name: "Test",
      text: "Hello",
      timestamp: DateTime.utc_now()
    }

    Router.handle_inbound(message)
    assert_receive {:reply_sent, 123, "Hello back!"}, 500
  end

  test "handles /reset command" do
    message = %{
      channel: :telegram,
      chat_id: 123,
      sender_id: 456,
      sender_name: "Test",
      text: "/reset",
      timestamp: DateTime.utc_now()
    }

    Router.handle_inbound(message)
    assert_receive {:reply_sent, 123, "Session reset."}, 500
  end

  test "handles /status command" do
    message = %{
      channel: :telegram,
      chat_id: 123,
      sender_id: 456,
      sender_name: "Test",
      text: "/status",
      timestamp: DateTime.utc_now()
    }

    Router.handle_inbound(message)
    assert_receive {:reply_sent, 123, text}, 500
    assert text =~ "gemini-3.0-pro-exp"
    assert text =~ "Messages: 0"
  end

  test "sends error message on LLM failure" do
    Clawdex.LLM.Stub.set_response({:error, :timeout})

    message = %{
      channel: :telegram,
      chat_id: 123,
      sender_id: 456,
      sender_name: "Test",
      text: "Hello",
      timestamp: DateTime.utc_now()
    }

    Router.handle_inbound(message)
    assert_receive {:reply_sent, 123, "Request timed out."}, 500
  end
end
