import Config

config :clawdex, ClawdexWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev-only-secret-key-base-that-is-at-least-64-bytes-long-for-development-use",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:clawdex, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:clawdex, ~w(--watch)]}
  ]

config :clawdex, ClawdexWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/clawdex_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :phoenix, :plug_init_mode, :runtime
