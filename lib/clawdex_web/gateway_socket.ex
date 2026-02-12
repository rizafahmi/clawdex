defmodule ClawdexWeb.GatewaySocket do
  use Phoenix.Socket

  alias Clawdex.Config.Loader

  channel "gateway:control", ClawdexWeb.GatewayChannel

  @impl true
  def connect(params, socket, _connect_info) do
    case validate_token(params) do
      :ok -> {:ok, socket}
      :error -> :error
    end
  end

  @impl true
  def id(_socket), do: nil

  defp validate_token(%{"token" => token}) do
    config = Loader.get()
    expected = get_in_map(config, [:gateway, :auth, :token])

    if expected && token == expected do
      :ok
    else
      :error
    end
  end

  defp validate_token(_), do: :error

  defp get_in_map(%{gateway: %{auth: %{token: token}}}, _), do: token
  defp get_in_map(_, _), do: nil
end
