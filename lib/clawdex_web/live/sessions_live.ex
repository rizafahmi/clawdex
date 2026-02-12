defmodule ClawdexWeb.SessionsLive do
  use ClawdexWeb, :live_view

  alias Clawdex.Session.SessionRegistry

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(5_000, self(), :refresh)
    end

    {:ok, assign_sessions(socket)}
  end

  @impl true
  def handle_event("reset", %{"key" => key}, socket) do
    Clawdex.Session.reset(key)
    {:noreply, assign_sessions(socket)}
  end

  def handle_event("delete", %{"key" => key}, socket) do
    SessionRegistry.stop(key)
    {:noreply, assign_sessions(socket)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign_sessions(socket)}
  end

  defp assign_sessions(socket) do
    sessions =
      SessionRegistry.list()
      |> Enum.map(fn key ->
        try do
          info = Clawdex.Session.get_info(key)
          history = Clawdex.Session.get_history(key)

          Map.put(
            info,
            :history,
            Enum.map(history, fn m -> %{role: m.role, content: m.content} end)
          )
        rescue
          _ -> %{session_key: key, message_count: 0, history: []}
        end
      end)

    assign(socket, page_title: "Sessions", sessions: sessions, selected: nil)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold">Sessions</h1>

      <div :if={@sessions == []} class="text-gray-500">No active sessions.</div>

      <div :for={session <- @sessions} class="rounded-lg bg-gray-900 border border-gray-800">
        <div class="flex items-center justify-between px-4 py-3 border-b border-gray-800">
          <div>
            <div class="font-mono text-sm">{session.session_key}</div>
            <div class="text-xs text-gray-500">{session.message_count} messages</div>
          </div>
          <div class="flex gap-2">
            <button
              phx-click="reset"
              phx-value-key={session.session_key}
              class="rounded bg-gray-700 px-3 py-1 text-xs text-gray-300 hover:bg-gray-600"
            >
              Reset
            </button>
            <button
              phx-click="delete"
              phx-value-key={session.session_key}
              class="rounded bg-red-900 px-3 py-1 text-xs text-red-300 hover:bg-red-800"
            >
              Delete
            </button>
          </div>
        </div>
        <div :if={session.history != []} class="max-h-64 overflow-y-auto p-4 space-y-2">
          <div :for={msg <- session.history} class="text-sm">
            <span class="text-gray-500">{msg.role}:</span>
            <span class="text-gray-300 ml-1">{msg.content}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
