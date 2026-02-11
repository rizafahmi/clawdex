defmodule Clawdex.RouterTest do
  use ExUnit.Case, async: false

  alias Clawdex.Config.Schema
  alias Clawdex.Router

  @config %Schema{
    agent: %{
      model: "gemini/gemini-2.5-flash",
      system_prompt: "Be helpful.",
      max_history_messages: 50,
      context_window_percent: 80
    },
    gemini: %{api_key: "test-key"},
    openrouter: %{api_key: "or-test-key"},
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
      chat_id: 9999,
      sender_id: 456,
      sender_name: "Test",
      text: "/status",
      timestamp: DateTime.utc_now()
    }

    Router.handle_inbound(message)
    assert_receive {:reply_sent, 9999, text}, 500
    assert text =~ "gemini/gemini-2.5-flash"
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

  test "handles /help command" do
    message = %{
      channel: :telegram,
      chat_id: 123,
      sender_id: 456,
      sender_name: "Test",
      text: "/help",
      timestamp: DateTime.utc_now()
    }

    Router.handle_inbound(message)
    assert_receive {:reply_sent, 123, text}, 500
    assert text =~ "/reset"
    assert text =~ "/model"
    assert text =~ "/compact"
  end

  test "handles /model command to show current model with doc links" do
    message = %{
      channel: :telegram,
      chat_id: 123,
      sender_id: 456,
      sender_name: "Test",
      text: "/model",
      timestamp: DateTime.utc_now()
    }

    Router.handle_inbound(message)
    assert_receive {:reply_sent, 123, text}, 500
    assert text =~ "gemini/gemini-2.5-flash"
    assert text =~ "Available models:"
    assert text =~ "https://ai.google.dev/gemini-api/docs/models"
    assert text =~ "https://openrouter.ai/models"
    refute text =~ "Anthropic"
  end

  test "/model shows anthropic link when anthropic key is configured" do
    config = %Schema{
      agent: %{
        model: "anthropic/claude-sonnet-4-20250514",
        system_prompt: "Be helpful.",
        max_history_messages: 50,
        context_window_percent: 80
      },
      gemini: %{api_key: "test-key"},
      anthropic: %{api_key: "anthropic-test-key"},
      channels: %{telegram: %{bot_token: "test-token"}}
    }

    stop_supervised!(Clawdex.Config.Loader)
    start_supervised!({Clawdex.Config.Loader, config: config})

    message = %{
      channel: :telegram,
      chat_id: 777,
      sender_id: 456,
      sender_name: "Test",
      text: "/model",
      timestamp: DateTime.utc_now()
    }

    Router.handle_inbound(message)
    assert_receive {:reply_sent, 777, text}, 500
    assert text =~ "anthropic/claude-sonnet-4-20250514"
    assert text =~ "https://platform.claude.com/docs/en/about-claude/models/overview"
    assert text =~ "https://ai.google.dev/gemini-api/docs/models"
    refute text =~ "OpenRouter"
  end

  test "handles /model <name> to switch model" do
    message = %{
      channel: :telegram,
      chat_id: 124,
      sender_id: 456,
      sender_name: "Test",
      text: "/model openai/gpt-4o",
      timestamp: DateTime.utc_now()
    }

    Router.handle_inbound(message)
    assert_receive {:reply_sent, 124, text}, 500
    assert text =~ "Model switched to: openai/gpt-4o"
  end

  test "sends error when unknown provider and no openrouter key" do
    Clawdex.LLM.Stub.set_response({:error, :unknown_provider})

    message = %{
      channel: :telegram,
      chat_id: 125,
      sender_id: 456,
      sender_name: "Test",
      text: "Hello",
      timestamp: DateTime.utc_now()
    }

    Router.handle_inbound(message)
    assert_receive {:reply_sent, 125, "Unknown model provider. Check model name."}, 500
  end
end
