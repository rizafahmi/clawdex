defmodule Clawdex.Config.Loader do
  @moduledoc false

  use GenServer

  alias Clawdex.Config.Schema

  @default_path Path.expand("~/.openclaw_ex/config.json")

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get() :: Schema.t()
  def get do
    GenServer.call(__MODULE__, :get)
  end

  @spec load() :: {:ok, Schema.t()} | {:error, term()}
  def load, do: load(config_path())

  @spec load(String.t()) :: {:ok, Schema.t()} | {:error, term()}
  def load(path) do
    with {:ok, contents} <- read_file(path),
         {:ok, decoded} <- decode_json(contents),
         {:ok, config} <- Schema.validate(decoded) do
      {:ok, config}
    end
  end

  @impl true
  def init(opts) do
    case Keyword.get(opts, :config) do
      %Schema{} = config ->
        {:ok, config}

      nil ->
        path = Keyword.get(opts, :path, config_path())

        case load(path) do
          {:ok, config} ->
            {:ok, config}

          {:error, reason} ->
            {:stop, {:config_error, reason}}
        end
    end
  end

  @impl true
  def handle_call(:get, _from, config) do
    {:reply, config, config}
  end

  defp config_path do
    System.get_env("OPENCLAW_CONFIG_PATH") || @default_path
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, _} = ok -> ok
      {:error, :enoent} -> {:error, "config file not found: #{path}"}
      {:error, reason} -> {:error, "failed to read config: #{reason}"}
    end
  end

  defp decode_json(contents) do
    case Jason.decode(contents) do
      {:ok, _} = ok -> ok
      {:error, _} -> {:error, "invalid JSON in config file"}
    end
  end
end
