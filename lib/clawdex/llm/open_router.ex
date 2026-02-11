defmodule Clawdex.LLM.OpenRouter do
  @moduledoc false

  @behaviour Clawdex.LLM.Behaviour

  @default_model "anthropic/claude-sonnet-4-20250514"
  @timeout 120_000

  @impl true
  def chat(messages, opts \\ []) do
    api_key = Keyword.fetch!(opts, :api_key)
    model = Keyword.get(opts, :model, @default_model)
    system = Keyword.get(opts, :system)
    base_url = opts[:base_url] || Application.get_env(:clawdex, :openrouter_base_url, "https://openrouter.ai/api/v1")

    api_messages = build_messages(system, messages)

    body = %{
      "model" => model,
      "messages" => api_messages
    }

    url = base_url <> "/chat/completions"

    headers = [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]

    case Req.post(url, json: body, headers: headers, receive_timeout: @timeout) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        extract_text(body)

      {:ok, %Req.Response{status: 401}} ->
        {:error, :invalid_api_key}

      {:ok, %Req.Response{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_messages(nil, messages), do: messages
  defp build_messages("", messages), do: messages

  defp build_messages(system, messages) do
    [%{"role" => "system", "content" => system} | messages]
  end

  defp extract_text(%{"choices" => [%{"message" => %{"content" => content}} | _]}) do
    {:ok, content}
  end

  defp extract_text(body) do
    {:error, {:unexpected_response, body}}
  end
end
