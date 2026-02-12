defmodule Clawdex.GatewayTest do
  use ExUnit.Case, async: false

  alias Clawdex.Config.Loader
  alias Clawdex.Config.Schema
  alias Clawdex.Gateway
  alias Clawdex.LLM.Stub
  alias Clawdex.Session
  alias Phoenix.PubSub

  @config %Schema{
    agent: %{
      model: "gemini/gemini-2.5-flash",
      system_prompt: "Be helpful.",
      max_history_messages: 50,
      context_window_percent: 80,
      tools: %{allow: ["bash"], deny: []},
      max_tool_iterations: 10
    },
    gemini: %{api_key: "test-key"},
    openrouter: %{api_key: "or-test-key"},
    channels: %{telegram: %{bot_token: "test-token"}}
  }

  setup do
    start_supervised!({Loader, config: @config})

    Stub.setup()
    Application.put_env(:clawdex, :llm_module, Stub)

    on_exit(fn ->
      Application.delete_env(:clawdex, :llm_module)
    end)

    :ok
  end

  test "send_text broadcasts chat events" do
    Stub.set_response({:ok, "Hello from LLM!"})

    session_key = "test:gateway_#{System.unique_integer([:positive])}"
    PubSub.subscribe(Clawdex.PubSub, "gateway:session:#{session_key}")

    Gateway.send_text(session_key, "Hello")

    assert_receive {:chat_event, %{type: "text", content: "Hello from LLM!"}}, 1000
    assert_receive {:chat_event, %{type: "done"}}, 1000
  end

  test "send_text broadcasts error on LLM failure" do
    Stub.set_response({:error, :timeout})

    session_key = "test:gateway_err_#{System.unique_integer([:positive])}"
    PubSub.subscribe(Clawdex.PubSub, "gateway:session:#{session_key}")

    Gateway.send_text(session_key, "Hello")

    assert_receive {:chat_event, %{type: "error", content: "Request timed out."}}, 1000
    assert_receive {:chat_event, %{type: "done"}}, 1000
  end

  test "send_text includes session_key in broadcast events" do
    Stub.set_response({:ok, "reply"})

    session_key = "test:gateway_sk_#{System.unique_integer([:positive])}"
    PubSub.subscribe(Clawdex.PubSub, "gateway:session:#{session_key}")

    Gateway.send_text(session_key, "Hi")

    assert_receive {:chat_event, %{type: "text", session_key: ^session_key}}, 1000
    assert_receive {:chat_event, %{type: "done", session_key: ^session_key}}, 1000
  end

  test "send_text stores messages in session history" do
    Stub.set_response({:ok, "Stored reply"})

    session_key = "test:gateway_hist_#{System.unique_integer([:positive])}"
    Gateway.send_text(session_key, "Remember this")

    history = Session.get_history(session_key)
    assert length(history) == 2

    assert Enum.at(history, 0).role == :user
    assert Enum.at(history, 0).content == "Remember this"
    assert Enum.at(history, 1).role == :assistant
    assert Enum.at(history, 1).content == "Stored reply"
  end

  test "subscribe subscribes to session topic" do
    session_key = "test:sub_#{System.unique_integer([:positive])}"
    Gateway.subscribe(session_key)

    PubSub.broadcast(
      Clawdex.PubSub,
      "gateway:session:#{session_key}",
      {:chat_event, %{type: "text", content: "test"}}
    )

    assert_receive {:chat_event, %{type: "text", content: "test"}}, 500
  end

  test "send_text handles different error reasons" do
    session_key = "test:gateway_errs_#{System.unique_integer([:positive])}"
    PubSub.subscribe(Clawdex.PubSub, "gateway:session:#{session_key}")

    for {reason, expected_msg} <- [
          {:invalid_api_key, "API key invalid. Check config."},
          {:rate_limited, "Rate limited, try again shortly."},
          {:unknown_provider, "Unknown model provider. Check model name."},
          {:something_else, "Something went wrong. Please try again."}
        ] do
      Stub.set_response({:error, reason})
      Gateway.send_text(session_key, "test")

      assert_receive {:chat_event, %{type: "error", content: ^expected_msg}}, 1000
      assert_receive {:chat_event, %{type: "done"}}, 1000
    end
  end
end
