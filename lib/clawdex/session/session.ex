defmodule Clawdex.Session do
  @moduledoc false

  use GenServer

  alias Clawdex.Session.Message

  @max_messages 50
  @idle_timeout :timer.minutes(30)

  defstruct [
    :session_key,
    :model,
    :created_at,
    :last_active_at,
    messages: []
  ]

  def start_link(session_key) do
    GenServer.start_link(__MODULE__, session_key,
      name: via(session_key)
    )
  end

  @spec append(String.t(), Message.t()) :: :ok
  def append(session_key, %Message{} = message) do
    GenServer.call(via(session_key), {:append, message})
  end

  @spec get_history(String.t()) :: [Message.t()]
  def get_history(session_key) do
    GenServer.call(via(session_key), :get_history)
  end

  @spec reset(String.t()) :: :ok
  def reset(session_key) do
    GenServer.call(via(session_key), :reset)
  end

  @spec get_info(String.t()) :: map()
  def get_info(session_key) do
    GenServer.call(via(session_key), :get_info)
  end

  defp via(session_key) do
    {:via, Registry, {Clawdex.Session.Registry, session_key}}
  end

  @impl true
  def init(session_key) do
    now = DateTime.utc_now()

    state = %__MODULE__{
      session_key: session_key,
      created_at: now,
      last_active_at: now,
      messages: []
    }

    {:ok, state, @idle_timeout}
  end

  @impl true
  def handle_call({:append, message}, _from, state) do
    messages =
      (state.messages ++ [message])
      |> Enum.take(-@max_messages)

    state = %{state | messages: messages, last_active_at: DateTime.utc_now()}
    {:reply, :ok, state, @idle_timeout}
  end

  @impl true
  def handle_call(:get_history, _from, state) do
    {:reply, state.messages, state, @idle_timeout}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    state = %{state | messages: [], last_active_at: DateTime.utc_now()}
    {:reply, :ok, state, @idle_timeout}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    info = %{
      session_key: state.session_key,
      message_count: length(state.messages),
      model: state.model,
      created_at: state.created_at,
      last_active_at: state.last_active_at
    }

    {:reply, info, state, @idle_timeout}
  end

  @impl true
  def handle_info(:timeout, state) do
    {:stop, :normal, state}
  end
end
