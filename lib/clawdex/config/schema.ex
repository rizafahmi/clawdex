defmodule Clawdex.Config.Schema do
  @moduledoc false

  defstruct [
    :agent,
    :gemini,
    :anthropic,
    :openrouter,
    :channels,
    :gateway
  ]

  @type t :: %__MODULE__{
          agent: agent(),
          gemini: gemini(),
          anthropic: anthropic() | nil,
          openrouter: openrouter() | nil,
          channels: channels(),
          gateway: gateway() | nil
        }

  @type agent :: %{
          model: String.t(),
          system_prompt: String.t(),
          max_history_messages: integer(),
          context_window_percent: integer(),
          workspace: String.t(),
          tools: tools_policy(),
          max_tool_iterations: integer()
        }

  @type tools_policy :: %{
          allow: [String.t()],
          deny: [String.t()]
        }

  @type gateway :: %{
          port: integer(),
          bind: String.t(),
          auth: %{token: String.t()}
        }

  @type gemini :: %{
          api_key: String.t()
        }

  @type anthropic :: %{
          api_key: String.t()
        }

  @type openrouter :: %{
          api_key: String.t()
        }

  @type channels :: %{
          telegram: telegram_config() | nil
        }

  @type telegram_config :: %{
          bot_token: String.t()
        }

  @spec validate(map()) :: {:ok, t()} | {:error, String.t()}
  def validate(raw) when is_map(raw) do
    with {:ok, agent} <- validate_agent(raw),
         {:ok, gemini} <- validate_gemini(raw),
         {:ok, channels} <- validate_channels(raw) do
      {:ok,
       %__MODULE__{
         agent: agent,
         gemini: gemini,
         anthropic: validate_anthropic(raw),
         openrouter: validate_openrouter(raw),
         channels: channels,
         gateway: validate_gateway(raw)
       }}
    end
  end

  def validate(_), do: {:error, "config must be a map"}

  defp validate_agent(%{"agent" => %{"model" => model} = agent}) when is_binary(model) do
    tools = validate_tools_policy(Map.get(agent, "tools", %{}))

    {:ok,
     %{
       model: model,
       system_prompt: Map.get(agent, "systemPrompt", "You are a helpful personal assistant."),
       max_history_messages: Map.get(agent, "maxHistoryMessages", 50),
       context_window_percent: Map.get(agent, "contextWindowPercent", 80),
       workspace: Map.get(agent, "workspace", "~/.clawdex/workspace"),
       tools: tools,
       max_tool_iterations: Map.get(agent, "maxToolIterations", 10)
     }}
  end

  defp validate_agent(%{"agent" => _}), do: {:error, "agent.model is required"}
  defp validate_agent(_), do: {:error, "agent config is required"}

  defp validate_gemini(%{"gemini" => %{"apiKey" => key}}) when is_binary(key) and key != "" do
    {:ok, %{api_key: key}}
  end

  defp validate_gemini(_) do
    case System.get_env("GEMINI_API_KEY") do
      nil -> {:error, "gemini.apiKey is required (config or GEMINI_API_KEY env var)"}
      "" -> {:error, "gemini.apiKey is required (config or GEMINI_API_KEY env var)"}
      key -> {:ok, %{api_key: key}}
    end
  end

  defp validate_anthropic(%{"anthropic" => %{"apiKey" => key}})
       when is_binary(key) and key != "" do
    %{api_key: key}
  end

  defp validate_anthropic(_) do
    case System.get_env("ANTHROPIC_API_KEY") do
      nil -> nil
      "" -> nil
      key -> %{api_key: key}
    end
  end

  defp validate_openrouter(%{"openrouter" => %{"apiKey" => key}})
       when is_binary(key) and key != "" do
    %{api_key: key}
  end

  defp validate_openrouter(_) do
    case System.get_env("OPENROUTER_API_KEY") do
      nil -> nil
      "" -> nil
      key -> %{api_key: key}
    end
  end

  defp validate_channels(%{"channels" => %{"telegram" => %{"botToken" => token}}})
       when is_binary(token) and token != "" do
    {:ok, %{telegram: %{bot_token: token}}}
  end

  defp validate_channels(_) do
    case System.get_env("TELEGRAM_BOT_TOKEN") do
      nil ->
        {:error, "channels.telegram.botToken is required (config or TELEGRAM_BOT_TOKEN env var)"}

      "" ->
        {:error, "channels.telegram.botToken is required (config or TELEGRAM_BOT_TOKEN env var)"}

      token ->
        {:ok, %{telegram: %{bot_token: token}}}
    end
  end

  defp validate_gateway(%{"gateway" => gw}) when is_map(gw) do
    token =
      case get_in(gw, ["auth", "token"]) do
        t when is_binary(t) and t != "" -> t
        _ -> nil
      end

    %{
      port: Map.get(gw, "port", 4000),
      bind: Map.get(gw, "bind", "loopback"),
      auth: %{token: token}
    }
  end

  defp validate_gateway(_), do: nil

  defp validate_tools_policy(tools) when is_map(tools) do
    %{
      allow: Map.get(tools, "allow", ["bash", "read", "write", "edit"]),
      deny: Map.get(tools, "deny", [])
    }
  end

  defp validate_tools_policy(_), do: %{allow: ["bash", "read", "write", "edit"], deny: []}
end
