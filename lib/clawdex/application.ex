defmodule Clawdex.Application do
  @moduledoc false

  use Application

  require Logger

  alias Clawdex.Config.Loader

  @impl true
  def start(_type, _args) do
    config_opts = config_opts()

    base_children =
      config_children(config_opts) ++
        repo_children() ++
        [
          {Phoenix.PubSub, name: Clawdex.PubSub},
          {Registry, keys: :unique, name: Clawdex.Session.Registry},
          {DynamicSupervisor, strategy: :one_for_one, name: Clawdex.Session.DynamicSupervisor},
          {Task.Supervisor, name: Clawdex.TaskSupervisor}
        ]

    opts = [strategy: :one_for_one, name: Clawdex.Supervisor]

    ensure_data_dir()

    with {:ok, sup} <- Supervisor.start_link(base_children, opts) do
      run_migrations()
      configure_telegex()
      start_optional_children(sup)
      {:ok, sup}
    end
  end

  defp configure_telegex do
    if Application.get_env(:clawdex, :start_telegram, true) and
         Application.get_env(:clawdex, :start_config, true) do
      config = Loader.get()
      Application.put_env(:telegex, :token, config.channels.telegram.bot_token)
    end
  end

  defp start_optional_children(sup) do
    for child <- channel_children() ++ endpoint_children() do
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
    case System.get_env("CLAWDEX_CONFIG_PATH") do
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

  defp ensure_data_dir do
    if Application.get_env(:clawdex, :start_repo, true) do
      db_path = Application.get_env(:clawdex, Clawdex.Repo)[:database] || ""

      case Path.dirname(db_path) do
        "." -> :ok
        dir -> File.mkdir_p!(dir)
      end
    end
  end

  defp run_migrations do
    if Application.get_env(:clawdex, :start_repo, true) do
      Ecto.Migrator.run(Clawdex.Repo, :up, all: true)
    end
  end

  defp repo_children do
    if Application.get_env(:clawdex, :start_repo, true) do
      [Clawdex.Repo]
    else
      []
    end
  end

  defp endpoint_children do
    if Application.get_env(:clawdex, :start_endpoint, true) do
      [ClawdexWeb.Endpoint]
    else
      []
    end
  end
end
