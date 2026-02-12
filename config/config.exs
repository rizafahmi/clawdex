import Config

config :clawdex,
  ecto_repos: [Clawdex.Repo]

config :clawdex, Clawdex.Repo, database: Path.expand("~/.clawdex/data/clawdex.db")

config :clawdex, ClawdexWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ClawdexWeb.ErrorHTML, json: ClawdexWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Clawdex.PubSub,
  live_view: [signing_salt: "O/djPQ6V4dEAr6pvP0j6zw=="]

config :esbuild,
  version: "0.25.0",
  clawdex: [
    args:
      ~w(js/app.js --bundle --target=es2020 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "4.1.0",
  clawdex: [
    args: ~w(
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

import_config "#{config_env()}.exs"
