defmodule Clawdex.Config.LoaderTest do
  use ExUnit.Case, async: true

  alias Clawdex.Config.Loader

  @valid_config %{
    "agent" => %{
      "model" => "gemini-3.0-pro-exp",
      "systemPrompt" => "You are helpful."
    },
    "gemini" => %{
      "apiKey" => "test-gemini-key"
    },
    "channels" => %{
      "telegram" => %{
        "botToken" => "123456:ABCDEF"
      }
    }
  }

  setup do
    dir = System.tmp_dir!() |> Path.join("clawdex_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "loads valid config file", %{dir: dir} do
    path = Path.join(dir, "config.json")
    File.write!(path, Jason.encode!(@valid_config))

    assert {:ok, config} = Loader.load(path)
    assert config.agent.model == "gemini-3.0-pro-exp"
    assert config.agent.system_prompt == "You are helpful."
    assert config.gemini.api_key == "test-gemini-key"
    assert config.channels.telegram.bot_token == "123456:ABCDEF"
  end

  test "returns error for missing file" do
    assert {:error, "config file not found:" <> _} = Loader.load("/nonexistent/path.json")
  end

  test "returns error for invalid JSON", %{dir: dir} do
    path = Path.join(dir, "bad.json")
    File.write!(path, "not json {{{")

    assert {:error, "invalid JSON in config file"} = Loader.load(path)
  end

  test "returns error for missing agent.model", %{dir: dir} do
    path = Path.join(dir, "config.json")
    config = put_in(@valid_config, ["agent", "model"], nil)
    File.write!(path, Jason.encode!(config))

    assert {:error, "agent.model is required"} = Loader.load(path)
  end

  test "uses default system prompt when not provided", %{dir: dir} do
    path = Path.join(dir, "config.json")
    config = update_in(@valid_config, ["agent"], &Map.delete(&1, "systemPrompt"))
    File.write!(path, Jason.encode!(config))

    assert {:ok, config} = Loader.load(path)
    assert config.agent.system_prompt == "You are a helpful personal assistant."
  end

  test "falls back to GEMINI_API_KEY env var", %{dir: dir} do
    path = Path.join(dir, "config.json")
    config = Map.delete(@valid_config, "gemini")
    File.write!(path, Jason.encode!(config))

    System.put_env("GEMINI_API_KEY", "env-key")
    on_exit(fn -> System.delete_env("GEMINI_API_KEY") end)

    assert {:ok, config} = Loader.load(path)
    assert config.gemini.api_key == "env-key"
  end

  test "falls back to TELEGRAM_BOT_TOKEN env var", %{dir: dir} do
    path = Path.join(dir, "config.json")
    config = Map.delete(@valid_config, "channels")
    File.write!(path, Jason.encode!(config))

    System.put_env("TELEGRAM_BOT_TOKEN", "env-token")
    on_exit(fn -> System.delete_env("TELEGRAM_BOT_TOKEN") end)

    assert {:ok, config} = Loader.load(path)
    assert config.channels.telegram.bot_token == "env-token"
  end
end
