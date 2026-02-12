defmodule Clawdex.Health do
  @moduledoc false

  use Plug.Router

  plug(:match)
  plug(:dispatch)

  alias Clawdex.Session.SessionRegistry

  get "/health" do
    sessions = length(SessionRegistry.list())

    body =
      Jason.encode!(%{
        status: "ok",
        sessions: sessions
      })

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, body)
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
