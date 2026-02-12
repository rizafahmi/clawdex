defmodule ClawdexWeb.ChatLive do
  use ClawdexWeb, :live_view

  alias Clawdex.Session.SessionRegistry

  @default_session_key "web:default"

  @impl true
  def mount(_params, _session, socket) do
    session_key = @default_session_key

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Clawdex.PubSub, "gateway:session:#{session_key}")
    end

    sessions = SessionRegistry.list()

    history =
      case SessionRegistry.lookup(session_key) do
        {:ok, _pid} ->
          Clawdex.Session.get_history(session_key)
          |> Enum.map(fn msg -> %{role: msg.role, content: msg.content} end)

        :not_found ->
          []
      end

    {:ok,
     assign(socket,
       page_title: "Chat",
       session_key: session_key,
       sessions: sessions,
       messages: history,
       input: "",
       processing: false
     )}
  end

  @impl true
  def handle_event("send_message", %{"message" => text}, socket) when text != "" do
    session_key = socket.assigns.session_key
    messages = socket.assigns.messages ++ [%{role: :user, content: text}]

    Task.Supervisor.start_child(Clawdex.TaskSupervisor, fn ->
      Clawdex.Gateway.send_text(session_key, text)
    end)

    {:noreply, assign(socket, messages: messages, input: "", processing: true)}
  end

  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("switch_session", %{"session_key" => key}, socket) do
    Phoenix.PubSub.unsubscribe(Clawdex.PubSub, "gateway:session:#{socket.assigns.session_key}")
    Phoenix.PubSub.subscribe(Clawdex.PubSub, "gateway:session:#{key}")

    history =
      case SessionRegistry.lookup(key) do
        {:ok, _pid} ->
          Clawdex.Session.get_history(key)
          |> Enum.map(fn msg -> %{role: msg.role, content: msg.content} end)

        :not_found ->
          []
      end

    {:noreply, assign(socket, session_key: key, messages: history, processing: false)}
  end

  @impl true
  def handle_info({:chat_event, %{type: "text", content: content}}, socket) do
    messages = socket.assigns.messages ++ [%{role: :assistant, content: content}]
    {:noreply, assign(socket, messages: messages, processing: false)}
  end

  def handle_info({:chat_event, %{type: "tool_use"} = event}, socket) do
    messages =
      socket.assigns.messages ++
        [%{role: :tool, content: "Using tool: #{event.tool_name}(#{Jason.encode!(event.input)})"}]

    {:noreply, assign(socket, messages: messages)}
  end

  def handle_info({:chat_event, %{type: "tool_result"} = event}, socket) do
    messages =
      socket.assigns.messages ++
        [%{role: :tool_result, content: event.output}]

    {:noreply, assign(socket, messages: messages)}
  end

  def handle_info({:chat_event, %{type: "done"}}, socket) do
    {:noreply, assign(socket, processing: false)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-[calc(100vh-8rem)]">
      <%!-- Sidebar --%>
      <div class="w-48 border-r border-gray-800 overflow-y-auto flex-shrink-0">
        <div class="p-3 text-xs font-semibold text-gray-400 uppercase">Sessions</div>
        <div
          :for={key <- @sessions}
          phx-click="switch_session"
          phx-value-session_key={key}
          class={[
            "px-3 py-2 cursor-pointer text-sm truncate",
            key == @session_key && "bg-gray-800 text-white",
            key != @session_key && "text-gray-400 hover:bg-gray-900"
          ]}
        >
          {key}
        </div>
      </div>

      <%!-- Chat area --%>
      <div class="flex-1 flex flex-col min-w-0">
        <div
          class="flex-1 overflow-y-auto p-4 space-y-4"
          id="messages"
          phx-hook="ScrollDown"
          data-count={length(@messages)}
        >
          <div :if={@messages == []} class="text-gray-500 text-center mt-8">
            Start a conversation.
          </div>
          <div
            :for={msg <- @messages}
            class={[
              "max-w-2xl rounded-lg px-4 py-2",
              msg.role == :user && "ml-auto bg-emerald-900/50 text-emerald-100",
              msg.role == :assistant && "bg-gray-800 text-gray-100 markdown",
              msg.role in [:tool, :tool_result] &&
                "bg-gray-900 border border-gray-700 font-mono text-xs text-gray-300"
            ]}
          >
            <div class="text-xs text-gray-500 mb-1">{msg.role}</div>
            <div :if={msg.role == :assistant} class="prose prose-invert max-w-none">
              {render_markdown(msg.content)}
            </div>
            <div :if={msg.role != :assistant} class="whitespace-pre-wrap">{msg.content}</div>
          </div>
          <div :if={@processing} class="flex items-center gap-2 text-gray-500">
            <span class="animate-pulse">Thinking...</span>
          </div>
        </div>

        <form phx-submit="send_message" class="border-t border-gray-800 p-4">
          <div class="flex gap-2">
            <input
              type="text"
              name="message"
              value={@input}
              placeholder="Type a message..."
              autocomplete="off"
              class="flex-1 rounded-lg bg-gray-800 border border-gray-700 px-4 py-2 text-gray-100 placeholder-gray-500 focus:border-emerald-500 focus:outline-none"
            />
            <button
              type="submit"
              disabled={@processing}
              class="rounded-lg bg-emerald-600 px-4 py-2 text-white hover:bg-emerald-500 disabled:opacity-50"
            >
              Send
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp render_markdown(content) do
    Earmark.as_html!(content) |> raw()
  end
end
