defmodule Clawdex.Session do
  @moduledoc false

  use GenServer

  alias Clawdex.Session.Message

  @max_messages 50
  @idle_timeout :timer.minutes(30)

  defstruct [
    :session_key,
    :model_override,
    :store_id,
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

  @spec set_model(String.t(), String.t()) :: :ok
  def set_model(session_key, model) do
    GenServer.call(via(session_key), {:set_model, model})
  end

  @spec get_model(String.t()) :: String.t() | nil
  def get_model(session_key) do
    GenServer.call(via(session_key), :get_model)
  end

  defp via(session_key) do
    {:via, Registry, {Clawdex.Session.Registry, session_key}}
  end

  @impl true
  def init(session_key) do
    now = DateTime.utc_now()

    {messages, model_override, store_id} = load_from_store(session_key)

    state = %__MODULE__{
      session_key: session_key,
      model_override: model_override,
      store_id: store_id,
      created_at: now,
      last_active_at: now,
      messages: messages
    }

    {:ok, state, @idle_timeout}
  end

  @impl true
  def handle_call({:append, message}, _from, state) do
    persist_message(state.store_id, message)

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
    clear_store(state.store_id)
    state = %{state | messages: [], model_override: nil, last_active_at: DateTime.utc_now()}
    {:reply, :ok, state, @idle_timeout}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    info = %{
      session_key: state.session_key,
      message_count: length(state.messages),
      model_override: state.model_override,
      created_at: state.created_at,
      last_active_at: state.last_active_at
    }

    {:reply, info, state, @idle_timeout}
  end

  @impl true
  def handle_call({:set_model, model}, _from, state) do
    persist_model_override(state.store_id, model)
    state = %{state | model_override: model, last_active_at: DateTime.utc_now()}
    {:reply, :ok, state, @idle_timeout}
  end

  @impl true
  def handle_call(:get_model, _from, state) do
    {:reply, state.model_override, state, @idle_timeout}
  end

  @impl true
  def handle_info(:timeout, state) do
    {:stop, :normal, state}
  end

  defp load_from_store(session_key) do
    if store_available?() do
      alias Clawdex.Session.Store

      case Store.find_or_create_session(session_key) do
        {:ok, record} ->
          messages =
            record.id
            |> Store.load_messages()
            |> Enum.map(fn msg ->
              Message.new(String.to_existing_atom(msg.role), msg.content)
            end)

          {messages, record.model_override, record.id}

        {:error, _} ->
          {[], nil, nil}
      end
    else
      {[], nil, nil}
    end
  end

  defp persist_message(nil, _message), do: :ok

  defp persist_message(store_id, %Message{} = message) do
    if store_available?() do
      Clawdex.Session.Store.append_message(store_id, %{
        role: to_string(message.role),
        content: message.content
      })
    end

    :ok
  end

  defp clear_store(nil), do: :ok

  defp clear_store(store_id) do
    if store_available?() do
      Clawdex.Session.Store.clear_messages(store_id)
    end

    :ok
  end

  defp persist_model_override(nil, _model), do: :ok

  defp persist_model_override(store_id, model) do
    if store_available?() do
      Clawdex.Session.Store.set_model_override(store_id, model)
    end

    :ok
  end

  defp store_available? do
    match?({:ok, _}, Application.fetch_env(:clawdex, :ecto_repos)) and
      Process.whereis(Clawdex.Repo) != nil
  end
end
