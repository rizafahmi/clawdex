import Config

config :clawdex,
  ecto_repos: [Clawdex.Repo]

config :clawdex, Clawdex.Repo, database: Path.expand("~/.clawdex/data/clawdex.db")

import_config "#{config_env()}.exs"
