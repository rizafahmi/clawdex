defmodule ClawdexWeb.ConfigLive do
  use ClawdexWeb, :live_view

  alias Clawdex.Config.Loader

  @impl true
  def mount(_params, _session, socket) do
    config =
      if Process.whereis(Loader) do
        try do
          Loader.get() |> redact_config()
        rescue
          _ -> %{error: "Failed to load config"}
        end
      else
        %{note: "Config loader not running"}
      end

    {:ok, assign(socket, page_title: "Config", config: config)}
  end

  defp redact_config(config) do
    %{
      agent: config.agent,
      gemini: redact_key(config.gemini),
      anthropic: redact_key(config.anthropic),
      openrouter: redact_key(config.openrouter),
      channels: %{
        telegram: redact_key(Map.get(config.channels, :telegram))
      }
    }
  end

  defp redact_key(nil), do: nil

  defp redact_key(map) when is_map(map) do
    Map.new(map, fn
      {:api_key, _} -> {:api_key, "••••••••"}
      {:bot_token, _} -> {:bot_token, "••••••••"}
      {k, v} -> {k, v}
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold">Configuration</h1>
      <div class="rounded-lg bg-gray-900 border border-gray-800 p-4">
        <pre class="text-sm text-gray-300 whitespace-pre-wrap font-mono">{inspect(@config, pretty: true, width: 80)}</pre>
      </div>
    </div>
    """
  end
end
