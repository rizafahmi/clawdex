defmodule Clawdex.LLM.Anthropic do
  @moduledoc false

  @behaviour Clawdex.LLM.Behaviour

  @default_model "claude-sonnet-4-20250514"
  @default_base_url "https://api.anthropic.com/v1"
  @default_max_tokens 8192
  @api_version "2023-06-01"
  @timeout 120_000

  @impl true
  def chat(messages, opts \\ []) do
    api_key = Keyword.fetch!(opts, :api_key)
    model = opts |> Keyword.get(:model, @default_model) |> normalize_model()
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)
    system = Keyword.get(opts, :system)
    base_url = opts[:base_url] || Application.get_env(:clawdex, :anthropic_base_url, @default_base_url)

    url = "#{base_url}/messages"
    body = build_body(messages, model, max_tokens, system)

    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", @api_version},
      {"content-type", "application/json"}
    ]

    Req.post(url, json: body, headers: headers, receive_timeout: @timeout)
    |> Clawdex.LLM.HTTP.map_response(&extract_text/1)
  end

  defp normalize_model("anthropic/" <> model), do: model
  defp normalize_model(model), do: model

  defp build_body(messages, model, max_tokens, system) do
    %{
      "model" => model,
      "messages" => messages,
      "max_tokens" => max_tokens
    }
    |> maybe_put_system(system)
  end

  defp maybe_put_system(body, nil), do: body
  defp maybe_put_system(body, ""), do: body
  defp maybe_put_system(body, system), do: Map.put(body, "system", system)

  defp extract_text(%{"content" => [%{"type" => "text", "text" => text} | _]}) do
    {:ok, text}
  end

  defp extract_text(body) do
    {:error, {:unexpected_response, body}}
  end
end
