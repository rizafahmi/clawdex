defmodule Clawdex.Config.SchemaTest do
  use ExUnit.Case, async: true

  alias Clawdex.Config.Schema

  @valid_raw %{
    "agent" => %{
      "model" => "gemini-2.5-flash",
      "systemPrompt" => "Be helpful.",
      "maxHistoryMessages" => 100,
      "contextWindowPercent" => 90
    },
    "gemini" => %{"apiKey" => "gemini-key"},
    "anthropic" => %{"apiKey" => "anthropic-key"},
    "openrouter" => %{"apiKey" => "openrouter-key"},
    "channels" => %{
      "telegram" => %{"botToken" => "123:ABC"}
    }
  }

  describe "validate/1" do
    test "returns valid config struct" do
      assert {:ok, %Schema{} = config} = Schema.validate(@valid_raw)
      assert config.agent.model == "gemini-2.5-flash"
      assert config.agent.system_prompt == "Be helpful."
      assert config.agent.max_history_messages == 100
      assert config.agent.context_window_percent == 90
      assert config.gemini.api_key == "gemini-key"
      assert config.anthropic.api_key == "anthropic-key"
      assert config.openrouter.api_key == "openrouter-key"
      assert config.channels.telegram.bot_token == "123:ABC"
    end

    test "uses default system prompt when not provided" do
      raw = update_in(@valid_raw, ["agent"], &Map.delete(&1, "systemPrompt"))
      assert {:ok, config} = Schema.validate(raw)
      assert config.agent.system_prompt == "You are a helpful personal assistant."
    end

    test "uses default max_history_messages when not provided" do
      raw = update_in(@valid_raw, ["agent"], &Map.delete(&1, "maxHistoryMessages"))
      assert {:ok, config} = Schema.validate(raw)
      assert config.agent.max_history_messages == 50
    end

    test "uses default context_window_percent when not provided" do
      raw = update_in(@valid_raw, ["agent"], &Map.delete(&1, "contextWindowPercent"))
      assert {:ok, config} = Schema.validate(raw)
      assert config.agent.context_window_percent == 80
    end

    test "returns error when agent is missing" do
      raw = Map.delete(@valid_raw, "agent")
      assert {:error, "agent config is required"} = Schema.validate(raw)
    end

    test "returns error when agent.model is missing" do
      raw = put_in(@valid_raw, ["agent", "model"], nil)
      assert {:error, "agent.model is required"} = Schema.validate(raw)
    end

    test "returns error when agent.model is not a string" do
      raw = put_in(@valid_raw, ["agent", "model"], 123)
      assert {:error, "agent.model is required"} = Schema.validate(raw)
    end

    test "returns error when input is not a map" do
      assert {:error, "config must be a map"} = Schema.validate("string")
      assert {:error, "config must be a map"} = Schema.validate(42)
    end

    test "anthropic is nil when key not provided and env var not set" do
      raw = Map.delete(@valid_raw, "anthropic")
      assert {:ok, config} = Schema.validate(raw)
      assert config.anthropic == nil
    end

    test "openrouter is nil when key not provided and env var not set" do
      raw = Map.delete(@valid_raw, "openrouter")
      assert {:ok, config} = Schema.validate(raw)
      assert config.openrouter == nil
    end

    test "anthropic key from empty string is treated as nil" do
      raw = put_in(@valid_raw, ["anthropic", "apiKey"], "")
      assert {:ok, config} = Schema.validate(raw)
      assert config.anthropic == nil
    end

    test "openrouter key from empty string is treated as nil" do
      raw = put_in(@valid_raw, ["openrouter", "apiKey"], "")
      assert {:ok, config} = Schema.validate(raw)
      assert config.openrouter == nil
    end
  end
end
