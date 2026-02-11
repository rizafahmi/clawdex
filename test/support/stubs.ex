defmodule Clawdex.LLM.Stub do
  @moduledoc false
  @behaviour Clawdex.LLM.Behaviour

  @table __MODULE__

  def setup do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end

    :ok
  end

  def set_response(response) do
    :ets.insert(@table, {:response, response})
  end

  @impl true
  def chat(messages, opts) do
    case :ets.lookup(@table, :response) do
      [{:response, fun}] when is_function(fun, 2) -> fun.(messages, opts)
      [{:response, response}] -> response
      [] -> {:ok, "stub response"}
    end
  end
end

defmodule Clawdex.Channel.Stub do
  @moduledoc false
  @behaviour Clawdex.Channel.Behaviour

  @table __MODULE__

  def setup(test_pid) do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end

    :ets.insert(@table, {:test_pid, test_pid})
    :ok
  end

  @impl true
  def send_reply(chat_id, text) do
    case :ets.lookup(@table, :test_pid) do
      [{:test_pid, pid}] -> send(pid, {:reply_sent, chat_id, text})
      [] -> :ok
    end

    {:ok, "msg_123"}
  end

  @impl true
  def edit_reply(chat_id, message_id, text) do
    case :ets.lookup(@table, :test_pid) do
      [{:test_pid, pid}] -> send(pid, {:reply_edited, chat_id, message_id, text})
      [] -> :ok
    end

    :ok
  end
end
