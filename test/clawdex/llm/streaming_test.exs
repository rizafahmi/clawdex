defmodule Clawdex.LLM.StreamingTest do
  use ExUnit.Case, async: true

  alias Clawdex.LLM.Streaming

  defmodule FakeChannel do
    @behaviour Clawdex.Channel.Behaviour

    def start(test_pid) do
      Agent.start_link(fn -> test_pid end, name: __MODULE__)
    end

    @impl true
    def send_reply(chat_id, text) do
      pid = Agent.get(__MODULE__, & &1)
      send(pid, {:send_reply, chat_id, text})
      {:ok, "msg_1"}
    end

    @impl true
    def edit_reply(chat_id, message_id, text) do
      pid = Agent.get(__MODULE__, & &1)
      send(pid, {:edit_reply, chat_id, message_id, text})
      :ok
    end
  end

  setup do
    {:ok, _} = FakeChannel.start(self())
    :ok
  end

  test "streams chunks and sends final message" do
    chunks = [
      %{content: String.duplicate("a", 100), done: false},
      %{content: " world", done: true}
    ]

    assert {:ok, text} = Streaming.stream_to_channel(chunks, 123, FakeChannel)
    assert text == String.duplicate("a", 100) <> " world"

    assert_receive {:send_reply, 123, _initial}, 500
  end

  test "sends single reply for short content" do
    chunks = [
      %{content: "Hi", done: false},
      %{content: " there", done: true}
    ]

    assert {:ok, "Hi there"} = Streaming.stream_to_channel(chunks, 123, FakeChannel)
    assert_receive {:send_reply, 123, "Hi there"}, 500
  end

  test "accumulates content from multiple chunks" do
    chunks = [
      %{content: "Hello ", done: false},
      %{content: "world ", done: false},
      %{content: "!", done: true}
    ]

    assert {:ok, "Hello world !"} = Streaming.stream_to_channel(chunks, 123, FakeChannel)
  end
end
