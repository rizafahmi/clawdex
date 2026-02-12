defmodule ClawdexWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :clawdex

  @session_options [
    store: :cookie,
    key: "_clawdex_key",
    signing_salt: "oti10yozg9Fjg4Y/LUxNsQ==",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  socket "/gateway/websocket", ClawdexWeb.GatewaySocket, websocket: true

  plug Plug.Static,
    at: "/",
    from: :clawdex,
    gzip: false,
    only: ClawdexWeb.static_paths()

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug ClawdexWeb.Router
end
