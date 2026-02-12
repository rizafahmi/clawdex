defmodule ClawdexWeb.HealthController do
  use ClawdexWeb, :controller

  alias Clawdex.Session.SessionRegistry

  def health(conn, _params) do
    sessions = length(SessionRegistry.list())

    json(conn, %{
      status: "ok",
      sessions: sessions
    })
  end
end
