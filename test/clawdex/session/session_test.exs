defmodule Clawdex.Session.SessionTest do
  use ExUnit.Case, async: false

  alias Clawdex.Session
  alias Clawdex.Session.{Message, SessionRegistry}

  setup do
    session_key = "test:#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = SessionRegistry.get_or_start(session_key)

    on_exit(fn -> SessionRegistry.stop(session_key) end)
    {:ok, session_key: session_key}
  end

  test "appends and retrieves messages", %{session_key: key} do
    msg = Message.new(:user, "Hello")
    :ok = Session.append(key, msg)

    history = Session.get_history(key)
    assert length(history) == 1
    assert hd(history).content == "Hello"
    assert hd(history).role == :user
  end

  test "maintains message order", %{session_key: key} do
    :ok = Session.append(key, Message.new(:user, "First"))
    :ok = Session.append(key, Message.new(:assistant, "Second"))
    :ok = Session.append(key, Message.new(:user, "Third"))

    history = Session.get_history(key)
    contents = Enum.map(history, & &1.content)
    assert contents == ["First", "Second", "Third"]
  end

  test "reset clears history", %{session_key: key} do
    :ok = Session.append(key, Message.new(:user, "Hello"))
    assert length(Session.get_history(key)) == 1

    :ok = Session.reset(key)
    assert Session.get_history(key) == []
  end

  test "get_info returns session metadata", %{session_key: key} do
    :ok = Session.append(key, Message.new(:user, "Hello"))

    info = Session.get_info(key)
    assert info.session_key == key
    assert info.message_count == 1
    assert %DateTime{} = info.created_at
  end

  test "caps at max messages", %{session_key: key} do
    for i <- 1..60 do
      :ok = Session.append(key, Message.new(:user, "msg #{i}"))
    end

    history = Session.get_history(key)
    assert length(history) == 50
    assert hd(history).content == "msg 11"
  end
end
