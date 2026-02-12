import Config

config :logger, level: :warning

config :clawdex,
  start_telegram: false,
  start_health: false,
  start_endpoint: false,
  start_config: false,
  start_repo: false

config :clawdex, Clawdex.Repo,
  database: "clawdex_test.db",
  pool: Ecto.Adapters.SQL.Sandbox

config :clawdex, ClawdexWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base:
    "test-only-secret-key-base-that-is-at-least-64-bytes-long-for-test-environment",
  server: false
