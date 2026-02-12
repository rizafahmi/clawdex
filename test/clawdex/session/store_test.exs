defmodule Clawdex.Session.StoreTest do
  use ExUnit.Case, async: false

  alias Clawdex.Session.Store
  alias Clawdex.Session.Store.{MessageRecord, SessionRecord}

  @test_db "store_test_#{System.unique_integer([:positive])}.db"

  setup_all do
    Application.put_env(:clawdex, Clawdex.Repo, database: @test_db, pool_size: 1)
    {:ok, pid} = Clawdex.Repo.start_link([])

    Ecto.Migrator.run(
      Clawdex.Repo,
      Path.join(:code.priv_dir(:clawdex), "repo/migrations"),
      :up,
      all: true
    )

    on_exit(fn ->
      Process.exit(pid, :normal)
      Process.sleep(50)
      File.rm(@test_db)
    end)

    :ok
  end

  setup do
    Clawdex.Repo.delete_all(MessageRecord)
    Clawdex.Repo.delete_all(SessionRecord)
    :ok
  end

  describe "find_or_create_session/1" do
    test "creates a new session" do
      assert {:ok, session} = Store.find_or_create_session("telegram:123")
      assert session.session_key == "telegram:123"
      assert session.channel == "telegram"
      assert session.chat_id == "123"
    end

    test "returns existing session" do
      {:ok, s1} = Store.find_or_create_session("telegram:123")
      {:ok, s2} = Store.find_or_create_session("telegram:123")
      assert s1.id == s2.id
    end
  end

  describe "append_message/2" do
    test "appends a message to a session" do
      {:ok, session} = Store.find_or_create_session("telegram:456")

      {:ok, msg} = Store.append_message(session.id, %{role: "user", content: "Hello"})
      assert msg.role == "user"
      assert msg.content == "Hello"
      assert msg.token_count > 0
    end
  end

  describe "load_messages/1" do
    test "loads messages in order" do
      {:ok, session} = Store.find_or_create_session("telegram:789")

      Store.append_message(session.id, %{role: "user", content: "Hello"})
      Store.append_message(session.id, %{role: "assistant", content: "Hi there!"})
      Store.append_message(session.id, %{role: "user", content: "How are you?"})

      messages = Store.load_messages(session.id)
      assert length(messages) == 3
      assert Enum.at(messages, 0).role == "user"
      assert Enum.at(messages, 1).role == "assistant"
      assert Enum.at(messages, 2).content == "How are you?"
    end
  end

  describe "clear_messages/1" do
    test "deletes all messages and resets count" do
      {:ok, session} = Store.find_or_create_session("telegram:111")

      Store.append_message(session.id, %{role: "user", content: "Hello"})
      Store.append_message(session.id, %{role: "assistant", content: "Hi"})

      assert length(Store.load_messages(session.id)) == 2

      Store.clear_messages(session.id)

      assert Store.load_messages(session.id) == []
    end
  end

  describe "set_model_override/2" do
    test "sets model override on session" do
      {:ok, session} = Store.find_or_create_session("telegram:222")

      Store.set_model_override(session.id, "openai/gpt-4o")

      updated = Store.get_session_by_key("telegram:222")
      assert updated.model_override == "openai/gpt-4o"
    end
  end
end
