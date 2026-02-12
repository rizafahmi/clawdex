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

      anthropic_model?(model_string) ->
        resolve_anthropic(model_string, config)

      true ->
        resolve_openrouter(model_string, config)
    end
  end

  defp resolve_anthropic(model_string, config) do
    case get_anthropic_key(config) do
      nil ->
        resolve_openrouter(model_string, config)

      api_key ->
        model_id = strip_prefix(model_string, "anthropic/")
        opts = [api_key: api_key, model: model_id]
        {:ok, {Clawdex.LLM.Anthropic, model_id, opts}}
    end
  end

  defp resolve_openrouter(model_string, config) do
    case get_openrouter_key(config) do
      nil ->
        {:error, :unknown_provider}

      api_key ->
        opts = [api_key: api_key, model: model_string]
        {:ok, {Clawdex.LLM.OpenRouter, model_string, opts}}
    end
  end

  defp gemini_model?("gemini/" <> _), do: true
  defp gemini_model?("gemini-" <> _), do: true
  defp gemini_model?(_), do: false

  defp anthropic_model?("anthropic/" <> _), do: true
  defp anthropic_model?(_), do: false

  defp strip_prefix("gemini/" <> rest, "gemini/"), do: rest
  defp strip_prefix("anthropic/" <> rest, "anthropic/"), do: rest
  defp strip_prefix(model, _), do: model

  defp get_anthropic_key(%{anthropic: %{api_key: key}}) when is_binary(key) and key != "",
    do: key

  defp get_anthropic_key(_), do: nil

  defp get_openrouter_key(%{openrouter: %{api_key: key}}) when is_binary(key) and key != "",
    do: key

  defp get_openrouter_key(_), do: nil
end
