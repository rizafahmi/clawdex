import Config

config :logger, level: :warning

config :clawdex,
  start_telegram: false,
  start_health: false,
  start_config: false,
  start_repo: false

config :clawdex, Clawdex.Repo,
  database: "clawdex_test.db",
  pool: Ecto.Adapters.SQL.Sandbox
