defmodule ClawdexWeb.GatewayChannelTest do
  use ExUnit.Case, async: false

  import Phoenix.ChannelTest

  alias Clawdex.Config.Loader
  alias Clawdex.Config.Schema
  alias Clawdex.Gateway
  alias Clawdex.LLM.Stub
  alias Clawdex.Session
  alias Clawdex.Session.SessionRegistry
  alias ClawdexWeb.GatewaySocket

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

  @endpoint ClawdexWeb.Endpoint

  setup do
    start_supervised!(ClawdexWeb.Endpoint)
    start_supervised!({Loader, config: @config})

    Stub.setup()
    Application.put_env(:clawdex, :llm_module, Stub)

    on_exit(fn ->
      Application.delete_env(:clawdex, :llm_module)
    end)

    {:ok, _, socket} =
      socket(GatewaySocket, nil, %{})
      |> subscribe_and_join(ClawdexWeb.GatewayChannel, "gateway:control")

    %{socket: socket}
  end

  test "health returns status and session count", %{socket: socket} do
    push(socket, "request", %{"id" => "1", "method" => "health"})

    assert_push "response", %{id: "1", result: %{status: "ok", channels: []}}
  end

  test "sessions.list returns a list", %{socket: socket} do
    push(socket, "request", %{"id" => "2", "method" => "sessions.list"})

    assert_push "response", %{id: "2", result: result}
    assert is_list(result)
  end

  test "sessions.list returns active sessions", %{socket: socket} do
    session_key = "test:chan_#{System.unique_integer([:positive])}"
    Stub.set_response({:ok, "hi"})
    Gateway.send_text(session_key, "hello")

    push(socket, "request", %{"id" => "3", "method" => "sessions.list"})

    assert_push "response", %{id: "3", result: result}
    assert is_list(result)
    assert Enum.any?(result, fn s -> s.session_key == session_key end)
  end

  test "sessions.reset resets a session", %{socket: socket} do
    session_key = "test:chan_reset_#{System.unique_integer([:positive])}"
    Stub.set_response({:ok, "hi"})
    Gateway.send_text(session_key, "hello")

    history = Session.get_history(session_key)
    assert history != []

    push(socket, "request", %{
      "id" => "4",
      "method" => "sessions.reset",
      "params" => %{"session_key" => session_key}
    })

    assert_push "response", %{id: "4", result: %{ok: true}}

    assert Session.get_history(session_key) == []
  end

  test "sessions.delete stops a session", %{socket: socket} do
    session_key = "test:chan_del_#{System.unique_integer([:positive])}"
    Stub.set_response({:ok, "hi"})
    Gateway.send_text(session_key, "hello")

    assert {:ok, _pid} = SessionRegistry.lookup(session_key)

    push(socket, "request", %{
      "id" => "5",
      "method" => "sessions.delete",
      "params" => %{"session_key" => session_key}
    })

    assert_push "response", %{id: "5", result: %{ok: true}}

    Process.sleep(50)
    assert :not_found = SessionRegistry.lookup(session_key)
  end

  test "models.list returns empty list", %{socket: socket} do
    push(socket, "request", %{"id" => "6", "method" => "models.list"})

    assert_push "response", %{id: "6", result: []}
  end

  test "unknown method returns error", %{socket: socket} do
    push(socket, "request", %{"id" => "7", "method" => "nonexistent"})

    assert_push "response", %{id: "7", error: %{code: 404, message: "Unknown method"}}
  end
end
