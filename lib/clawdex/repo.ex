defmodule Clawdex.Repo do
  use Ecto.Repo,
    otp_app: :clawdex,
    adapter: Ecto.Adapters.SQLite3
end
