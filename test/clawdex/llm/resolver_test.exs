defmodule Clawdex.LLM.ResolverTest do
  use ExUnit.Case, async: true

  alias Clawdex.Config.Schema
  alias Clawdex.LLM.Resolver

  @config %Schema{
    agent: %{model: "gemini/gemini-2.5-flash", system_prompt: "Be helpful."},
    gemini: %{api_key: "gemini-key"},
    anthropic: %{api_key: "anthropic-key"},
    openrouter: %{api_key: "openrouter-key"},
    channels: %{telegram: %{bot_token: "test-token"}}
  }

  describe "resolve/2" do
    test "resolves gemini/ prefixed model to Gemini provider" do
      assert {:ok, {Clawdex.LLM.Gemini, "gemini-2.5-flash", opts}} =
               Resolver.resolve("gemini/gemini-2.5-flash", @config)

      assert opts[:api_key] == "gemini-key"
      assert opts[:model] == "gemini-2.5-flash"
    end

    test "resolves bare gemini-* model to Gemini provider" do
      assert {:ok, {Clawdex.LLM.Gemini, "gemini-2.5-flash", opts}} =
               Resolver.resolve("gemini-2.5-flash", @config)

      assert opts[:api_key] == "gemini-key"
    end

    test "resolves anthropic/ model to Anthropic when key is present" do
      assert {:ok, {Clawdex.LLM.Anthropic, "claude-sonnet-4-20250514", opts}} =
               Resolver.resolve("anthropic/claude-sonnet-4-20250514", @config)

      assert opts[:api_key] == "anthropic-key"
      assert opts[:model] == "claude-sonnet-4-20250514"
    end

    test "resolves anthropic/ model to OpenRouter when anthropic key is missing" do
      config = %{@config | anthropic: nil}

      assert {:ok, {Clawdex.LLM.OpenRouter, "anthropic/claude-sonnet-4-20250514", opts}} =
               Resolver.resolve("anthropic/claude-sonnet-4-20250514", config)

      assert opts[:api_key] == "openrouter-key"
      assert opts[:model] == "anthropic/claude-sonnet-4-20250514"
    end

    test "resolves openai/ model to OpenRouter" do
      assert {:ok, {Clawdex.LLM.OpenRouter, "openai/gpt-4o", opts}} =
               Resolver.resolve("openai/gpt-4o", @config)

      assert opts[:api_key] == "openrouter-key"
    end

    test "resolves meta-llama/ model to OpenRouter" do
      assert {:ok, {Clawdex.LLM.OpenRouter, "meta-llama/llama-4-maverick", opts}} =
               Resolver.resolve("meta-llama/llama-4-maverick", @config)

      assert opts[:api_key] == "openrouter-key"
    end

    test "returns error when openrouter key is missing for non-gemini model" do
      config = %{@config | anthropic: nil, openrouter: nil}

      assert {:error, :unknown_provider} =
               Resolver.resolve("anthropic/claude-sonnet-4-20250514", config)
    end
  end
end
