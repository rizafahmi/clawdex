defmodule Clawdex.LLM.HTTP do
  @moduledoc false

  @spec map_response(
          {:ok, Req.Response.t()} | {:error, term()},
          (map() -> {:ok, String.t()} | {:error, term()})
        ) :: {:ok, String.t()} | {:error, term()}
  def map_response({:ok, %Req.Response{status: 200, body: body}}, extract_fun),
    do: extract_fun.(body)

  def map_response({:ok, %Req.Response{status: 400, body: body}}, _extract_fun),
    do: {:error, {:bad_request, body}}

  def map_response({:ok, %Req.Response{status: 401}}, _extract_fun),
    do: {:error, :invalid_api_key}

  def map_response({:ok, %Req.Response{status: 429}}, _extract_fun),
    do: {:error, :rate_limited}

  def map_response({:ok, %Req.Response{status: status, body: body}}, _extract_fun),
    do: {:error, {:api_error, status, body}}

  def map_response({:error, %Req.TransportError{reason: :timeout}}, _extract_fun),
    do: {:error, :timeout}

  def map_response({:error, reason}, _extract_fun),
    do: {:error, reason}
end
