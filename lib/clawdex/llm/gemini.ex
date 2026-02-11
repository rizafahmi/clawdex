defmodule Clawdex.LLM.Gemini do
  @moduledoc false

  @behaviour Clawdex.LLM.Behaviour

  # Default to Gemini 3.0 Pro
  @default_model "gemini-2.5-flash"
  @timeout 120_000

  @impl true
  def chat(messages, opts \\ []) do
    api_key = Keyword.fetch!(opts, :api_key)
    model = Keyword.get(opts, :model, @default_model)
    system = Keyword.get(opts, :system)

    # Gemini API uses `contents` and `role` logic slightly differently.
    # We need to transform `messages` into `contents`.
    contents = Enum.map(messages, &to_gemini_content/1)

    url = api_url(model, api_key)

    body =
      %{
        "contents" => contents,
        "generationConfig" => %{
          "temperature" => 0.7
        }
      }
      |> maybe_put_system(system)

    case Req.post(url, json: body, receive_timeout: @timeout) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        extract_text(body)

      {:ok, %Req.Response{status: 400, body: body}} ->
        {:error, {:bad_request, body}}

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

  defp api_url(model, key) do
    # Normalize model name, remove prefix if present
    model = normalize_model(model)
    base = Application.get_env(:clawdex, :gemini_base_url, "https://generativelanguage.googleapis.com/v1beta/models")
    "#{base}/#{model}:generateContent?key=#{key}"
  end

  defp normalize_model("gemini/" <> model), do: model
  defp normalize_model(model), do: model

  # Transform standard message format to Gemini content
  defp to_gemini_content(%{"role" => "user", "content" => text}) do
    %{"role" => "user", "parts" => [%{"text" => text}]}
  end

  defp to_gemini_content(%{"role" => "assistant", "content" => text}) do
    %{"role" => "model", "parts" => [%{"text" => text}]}
  end

  # Gemini 1.5 Pro supports system instructions via `systemInstruction` field in specific format
  defp maybe_put_system(body, nil), do: body
  defp maybe_put_system(body, ""), do: body
  defp maybe_put_system(body, system) do
    Map.put(body, "systemInstruction", %{
      "parts" => [%{"text" => system}]
    })
  end

  defp extract_text(%{"candidates" => [%{"content" => %{"parts" => [%{"text" => text} | _]}} | _]}) do
    {:ok, text}
  end

  defp extract_text(%{"candidates" => [%{"finishReason" => "SAFETY"} | _]}) do
    {:ok, "[Response blocked due to safety settings]"}
  end

  defp extract_text(body) do
    {:error, {:unexpected_response, body}}
  end
end
