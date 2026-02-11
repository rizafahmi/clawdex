defmodule Clawdex.LLM.Gemini do
  @moduledoc false

  @behaviour Clawdex.LLM.Behaviour

  # Default to Gemini 2.5 Flash
  @default_model "gemini-2.5-flash"
  @default_base_url "https://generativelanguage.googleapis.com/v1beta/models"
  @timeout 120_000

  @impl true
  def chat(messages, opts \\ []) do
    api_key = Keyword.fetch!(opts, :api_key)
    model = opts |> Keyword.get(:model, @default_model) |> normalize_model()
    base_url = opts[:base_url] || Application.get_env(:clawdex, :gemini_base_url, @default_base_url)

    url = "#{base_url}/#{model}:generateContent"
    body = build_body(messages, opts)

    Req.post(url, json: body, params: [key: api_key], receive_timeout: @timeout)
    |> Clawdex.LLM.HTTP.map_response(&extract_text/1)
  end

  defp normalize_model("gemini/" <> model), do: model
  defp normalize_model(model), do: model

  defp build_body(messages, opts) do
    contents = Enum.map(messages, &to_gemini_content/1)

    %{
      "contents" => contents,
      "generationConfig" => %{
        "temperature" => 0.7
      }
    }
    |> maybe_put_system(opts[:system])
  end

  defp to_gemini_content(%{"role" => "user", "content" => text}) do
    %{"role" => "user", "parts" => [%{"text" => text}]}
  end

  defp to_gemini_content(%{"role" => "assistant", "content" => text}) do
    %{"role" => "model", "parts" => [%{"text" => text}]}
  end

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
