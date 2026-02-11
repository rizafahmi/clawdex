defmodule Clawdex.LLM.Anthropic do
  @moduledoc false

  @behaviour Clawdex.LLM.Behaviour

  @api_version "2023-06-01"
  @default_max_tokens 4096
  @timeout 120_000

  @impl true
  def chat(messages, opts \\ []) do
    api_key = Keyword.fetch!(opts, :api_key)
    model = Keyword.get(opts, :model, "claude-sonnet-4-20250514")
    system = Keyword.get(opts, :system)
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)

    body =
      %{
        "model" => normalize_model(model),
        "max_tokens" => max_tokens,
        "messages" => messages
      }
      |> maybe_put_system(system)

    case do_request(body, api_key) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        extract_text(body)

      {:ok, %Req.Response{status: 401}} ->
        {:error, :invalid_api_key}

      {:ok, %Req.Response{status: 429}} ->
        retry_after_rate_limit(body, api_key)

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        {:error, {:api_error, status, resp_body}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_request(body, api_key) do
    Req.post(api_url(),
      json: body,
      headers: [
        {"x-api-key", api_key},
        {"anthropic-version", @api_version},
        {"content-type", "application/json"}
      ],
      receive_timeout: @timeout
    )
  end

  defp api_url do
    Application.get_env(:clawdex, :anthropic_url, "https://api.anthropic.com/v1/messages")
  end

  defp extract_text(%{"content" => [%{"text" => text} | _]}) do
    {:ok, text}
  end

  defp extract_text(body) do
    {:error, {:unexpected_response, body}}
  end

  defp retry_after_rate_limit(body, api_key) do
    Process.sleep(2_000)

    case do_request(body, api_key) do
      {:ok, %Req.Response{status: 200, body: resp_body}} ->
        extract_text(resp_body)

      {:ok, %Req.Response{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        {:error, {:api_error, status, resp_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_model("anthropic/" <> model), do: model
  defp normalize_model(model), do: model

  defp maybe_put_system(body, nil), do: body
  defp maybe_put_system(body, ""), do: body
  defp maybe_put_system(body, system), do: Map.put(body, "system", system)
end
