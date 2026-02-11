import Config

if config_path = System.get_env("CLAWDEX_CONFIG_PATH") do
  config :clawdex, config_path: config_path
end
