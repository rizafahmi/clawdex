defmodule ClawdexWeb.GatewayChannel do
  @moduledoc false

  use ClawdexWeb, :channel

  alias Clawdex.Session
  alias Clawdex.Session.SessionRegistry

  @impl true
  def join("gateway:control", _payload, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_in("request", %{"method" => method} = payload, socket) do
    id = Map.get(payload, "id")
    params = Map.get(payload, "params", %{})

    case dispatch(method, params) do
      {:ok, result} ->
        push(socket, "response", %{id: id, result: result})

      {:error, error} ->
        push(socket, "response", %{id: id, error: error})
    end

    {:noreply, socket}
  end

  defp dispatch("health", _params) do
    sessions = SessionRegistry.list()

    {:ok,
     %{
       status: "ok",
       sessions: length(sessions),
       channels: []
     }}
  end

  defp dispatch("sessions.list", _params) do
    sessions = SessionRegistry.list()

    result =
      Enum.map(sessions, fn session_key ->
        info = Session.get_info(session_key)

        %{
          session_key: info.session_key,
          message_count: info.message_count,
          last_active: info.last_active_at
        }
      end)

    {:ok, result}
  end

  defp dispatch("sessions.reset", %{"session_key" => session_key}) do
    Session.reset(session_key)
    {:ok, %{ok: true}}
  end

  defp dispatch("sessions.delete", %{"session_key" => session_key}) do
    SessionRegistry.stop(session_key)
    {:ok, %{ok: true}}
  end

  defp dispatch("models.list", _params) do
    {:ok, []}
  end

  defp dispatch(_method, _params) do
    {:error, %{code: 404, message: "Unknown method"}}
  end
end
