defmodule ClawdexWeb.DashboardLive do
  use ClawdexWeb, :live_view

  alias Clawdex.Config.Loader
  alias Clawdex.Session
  alias Clawdex.Session.SessionRegistry

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Clawdex.PubSub, "gateway:system")
      :timer.send_interval(5_000, self(), :refresh)
    end

    {:ok, assign_stats(socket)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign_stats(socket)}
  end

  def handle_info(_msg, socket) do
    {:noreply, assign_stats(socket)}
  end

  defp assign_stats(socket) do
    sessions = SessionRegistry.list()

    session_details =
      Enum.map(sessions, fn key ->
        try do
          Session.get_info(key)
        rescue
          _ -> %{session_key: key, message_count: 0, last_active_at: nil}
        end
      end)

    config_loaded? = Process.whereis(Loader) != nil

    model =
      if config_loaded? do
        try do
          Loader.get().agent.model
        rescue
          _ -> "unknown"
        end
      else
        "not configured"
      end

    assign(socket,
      page_title: "Dashboard",
      status: :ok,
      session_count: length(sessions),
      sessions: session_details,
      model: model,
      uptime: uptime()
    )
  end

  defp uptime do
    {time, _} = :erlang.statistics(:wall_clock)
    seconds = div(time, 1000)
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)
    "#{hours}h #{minutes}m #{secs}s"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold">Dashboard</h1>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <div class="rounded-lg bg-gray-900 p-4 border border-gray-800">
          <div class="text-sm text-gray-400">Status</div>
          <div class="mt-1 flex items-center gap-2">
            <span class="h-3 w-3 rounded-full bg-emerald-500"></span>
            <span class="text-lg font-semibold">Online</span>
          </div>
        </div>

        <div class="rounded-lg bg-gray-900 p-4 border border-gray-800">
          <div class="text-sm text-gray-400">Sessions</div>
          <div class="mt-1 text-lg font-semibold">{@session_count}</div>
        </div>

        <div class="rounded-lg bg-gray-900 p-4 border border-gray-800">
          <div class="text-sm text-gray-400">Model</div>
          <div class="mt-1 text-lg font-semibold truncate">{@model}</div>
        </div>

        <div class="rounded-lg bg-gray-900 p-4 border border-gray-800">
          <div class="text-sm text-gray-400">Uptime</div>
          <div class="mt-1 text-lg font-semibold">{@uptime}</div>
        </div>
      </div>

      <div class="rounded-lg bg-gray-900 border border-gray-800">
        <div class="px-4 py-3 border-b border-gray-800">
          <h2 class="text-lg font-semibold">Active Sessions</h2>
        </div>
        <div :if={@sessions == []} class="p-4 text-gray-500">
          No active sessions.
        </div>
        <div :if={@sessions != []} class="divide-y divide-gray-800">
          <div :for={session <- @sessions} class="flex items-center justify-between px-4 py-3">
            <div>
              <div class="font-mono text-sm">{session.session_key}</div>
              <div class="text-xs text-gray-500">{session.message_count} messages</div>
            </div>
            <div class="text-xs text-gray-500">
              {if session[:last_active_at],
                do: Calendar.strftime(session.last_active_at, "%H:%M:%S"),
                else: "-"}
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
