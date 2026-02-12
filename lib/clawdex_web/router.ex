defmodule ClawdexWeb.Router do
  use ClawdexWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ClawdexWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ClawdexWeb do
    pipe_through :browser

    live "/", DashboardLive
    live "/chat", ChatLive
    live "/sessions", SessionsLive
    live "/config", ConfigLive
  end

  scope "/api", ClawdexWeb do
    pipe_through :api

    get "/health", HealthController, :health
  end
end
