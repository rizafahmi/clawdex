defmodule Clawdex.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    config_opts = config_opts()

    base_children =
      config_children(config_opts) ++
        [
          {Registry, keys: :unique, name: Clawdex.Session.Registry},
          {DynamicSupervisor, strategy: :one_for_one, name: Clawdex.Session.DynamicSupervisor},
          {Task.Supervisor, name: Clawdex.TaskSupervisor}
        ]

    opts = [strategy: :one_for_one, name: Clawdex.Supervisor]

    with {:ok, sup} <- Supervisor.start_link(base_children, opts) do
      configure_telegex()
      start_optional_children(sup)
      {:ok, sup}
    end
  end

  defp configure_telegex do
    if Application.get_env(:clawdex, :start_telegram, true) and
         Application.get_env(:clawdex, :start_config, true) do
      config = Clawdex.Config.Loader.get()
      Application.put_env(:telegex, :token, config.channels.telegram.bot_token)
    end
  end

  defp start_optional_children(sup) do
    for child <- channel_children() ++ health_children() do
      Supervisor.start_child(sup, child)
    end
  end

  defp config_children(config_opts) do
    if Application.get_env(:clawdex, :start_config, true) do
      [{Clawdex.Config.Loader, config_opts}]
    else
      []
    end
  end

  defp config_opts do
    case System.get_env("OPENCLAW_CONFIG_PATH") do
      nil -> []
      path -> [path: path]
    end
  end

  defp channel_children do
    if Application.get_env(:clawdex, :start_telegram, true) do
      [Clawdex.Channel.Telegram]
    else
      []
    end
  end

  defp health_children do
    if Application.get_env(:clawdex, :start_health, true) do
      port = Application.get_env(:clawdex, :health_port, 4000)
      [{Bandit, plug: Clawdex.Health, port: port}]
    else
      []
    end
  end
end
