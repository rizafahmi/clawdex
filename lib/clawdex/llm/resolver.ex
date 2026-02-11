defmodule Clawdex.LLM.Resolver do
  @moduledoc false

  alias Clawdex.Config.Schema

  @spec resolve(String.t(), Schema.t()) ::
          {:ok, {module(), String.t(), keyword()}} | {:error, :unknown_provider}
  def resolve(model_string, config) do
    case Application.get_env(:clawdex, :llm_module) do
      nil -> do_resolve(model_string, config)
      module -> {:ok, {module, model_string, [api_key: "test-key", model: model_string]}}
    end
  end

  defp do_resolve(model_string, config) do
    cond do
      gemini_model?(model_string) ->
        model_id = strip_prefix(model_string, "gemini/")
        opts = [api_key: config.gemini.api_key, model: model_id]
        {:ok, {Clawdex.LLM.Gemini, model_id, opts}}

      true ->
        case get_openrouter_key(config) do
          nil ->
            {:error, :unknown_provider}

          api_key ->
            opts = [api_key: api_key, model: model_string]
            {:ok, {Clawdex.LLM.OpenRouter, model_string, opts}}
        end
    end
  end

  defp gemini_model?("gemini/" <> _), do: true
  defp gemini_model?("gemini-" <> _), do: true
  defp gemini_model?(_), do: false

  defp strip_prefix("gemini/" <> rest, "gemini/"), do: rest
  defp strip_prefix(model, _), do: model

  defp get_openrouter_key(%{openrouter: %{api_key: key}}) when is_binary(key) and key != "",
    do: key

  defp get_openrouter_key(_), do: nil
end
