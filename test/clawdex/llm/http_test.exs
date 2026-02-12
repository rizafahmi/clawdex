defmodule Clawdex.LLM.HTTPTest do
  use ExUnit.Case, async: true

  alias Clawdex.LLM.HTTP

  describe "map_response/2" do
    test "returns extracted body on 200 OK" do
      response = {:ok, %Req.Response{status: 200, body: %{"data" => "success"}}}
      extract_fun = fn body -> {:ok, body["data"]} end

      assert {:ok, "success"} = HTTP.map_response(response, extract_fun)
    end

    test "returns extracted error from extract_fun on 200 OK" do
      response = {:ok, %Req.Response{status: 200, body: %{"error" => "fail"}}}
      extract_fun = fn _body -> {:error, :custom_error} end

      assert {:error, :custom_error} = HTTP.map_response(response, extract_fun)
    end

    test "returns {:error, {:bad_request, body}} on 400 Bad Request" do
      body = %{"message" => "Invalid input"}
      response = {:ok, %Req.Response{status: 400, body: body}}

      assert {:error, {:bad_request, ^body}} = HTTP.map_response(response, fn _ -> :ok end)
    end

    test "returns {:error, :invalid_api_key} on 401 Unauthorized" do
      response = {:ok, %Req.Response{status: 401, body: "Unauthorized"}}

      assert {:error, :invalid_api_key} = HTTP.map_response(response, fn _ -> :ok end)
    end

    test "returns {:error, :rate_limited} on 429 Too Many Requests" do
      response = {:ok, %Req.Response{status: 429, body: "Too Many Requests"}}

      assert {:error, :rate_limited} = HTTP.map_response(response, fn _ -> :ok end)
    end

    test "returns {:error, {:api_error, status, body}} on other status codes" do
      body = %{"error" => "Server Error"}
      response = {:ok, %Req.Response{status: 500, body: body}}

      assert {:error, {:api_error, 500, ^body}} = HTTP.map_response(response, fn _ -> :ok end)
    end

    test "returns {:error, :timeout} on timeout error" do
      error = {:error, %Req.TransportError{reason: :timeout}}

      assert {:error, :timeout} = HTTP.map_response(error, fn _ -> :ok end)
    end

    test "returns {:error, reason} on other errors" do
      error = {:error, :connection_refused}

      assert {:error, :connection_refused} = HTTP.map_response(error, fn _ -> :ok end)
    end
  end
end
