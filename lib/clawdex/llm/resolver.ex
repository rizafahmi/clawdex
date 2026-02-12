defmodule Clawdex.LLM.Resolver do
  @moduledoc false

  alias Clawdex.Config.Schema
  alias Clawdex.LLM.{Anthropic, Gemini, OpenRouter}

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
        model_id = String.replace_prefix(model_string, "gemini/", "")
        opts = [api_key: config.gemini.api_key, model: model_id]
        {:ok, {Gemini, model_id, opts}}

      anthropic_model?(model_string) ->
        resolve_anthropic(model_string, config)

      true ->
        resolve_openrouter(model_string, config)
    end
  end

  defp resolve_anthropic(model_string, config) do
    case get_valid_key(config.anthropic) do
      nil ->
        resolve_openrouter(model_string, config)

      api_key ->
        model_id = String.replace_prefix(model_string, "anthropic/", "")
        opts = [api_key: api_key, model: model_id]
        {:ok, {Anthropic, model_id, opts}}
    end
  end

  defp resolve_openrouter(model_string, config) do
    case get_valid_key(config.openrouter) do
      nil ->
        {:error, :unknown_provider}

      api_key ->
        opts = [api_key: api_key, model: model_string]
        {:ok, {OpenRouter, model_string, opts}}
    end
  end

  defp gemini_model?("gemini/" <> _), do: true
  defp gemini_model?("gemini-" <> _), do: true
  defp gemini_model?(_), do: false

  defp anthropic_model?("anthropic/" <> _), do: true
  defp anthropic_model?(_), do: false

  defp get_valid_key(%{api_key: key}) when is_binary(key) and key != "", do: key
  defp get_valid_key(_), do: nil
end
