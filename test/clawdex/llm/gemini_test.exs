defmodule Clawdex.LLM.GeminiTest do
  use ExUnit.Case, async: true

  alias Clawdex.LLM.Gemini

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  test "sends request to Gemini API and returns text", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1beta/models/gemini-pro:generateContent", fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      assert body =~ "Hello Gemini"
      assert conn.query_params["key"] == "test-key"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{
        "candidates" => [
          %{
            "content" => %{
              "parts" => [%{"text" => "Hello from Gemini"}]
            }
          }
        ]
      }))
    end)

    # We need to configure the base URL to point to bypass
    original_env = Application.get_env(:clawdex, :gemini_base_url)
    Application.put_env(:clawdex, :gemini_base_url, "http://localhost:#{bypass.port}/v1beta/models")

    on_exit(fn ->
      if original_env do
        Application.put_env(:clawdex, :gemini_base_url, original_env)
      else
        Application.delete_env(:clawdex, :gemini_base_url)
      end
    end)

    messages = [%{"role" => "user", "content" => "Hello Gemini"}]
    opts = [api_key: "test-key", model: "gemini-pro"]

    assert {:ok, "Hello from Gemini"} = Gemini.chat(messages, opts)
  end

  test "handles safety blockage", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1beta/models/gemini-pro:generateContent", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{
        "candidates" => [
          %{"finishReason" => "SAFETY"}
        ]
      }))
    end)

    Application.put_env(:clawdex, :gemini_base_url, "http://localhost:#{bypass.port}/v1beta/models")

    messages = [%{"role" => "user", "content" => "Unsafe content"}]
    opts = [api_key: "test-key", model: "gemini-pro"]

    assert {:ok, "[Response blocked due to safety settings]"} = Gemini.chat(messages, opts)
  end

  test "handles API errors", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1beta/models/gemini-pro:generateContent", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(400, Jason.encode!(%{"error" => "Bad Request"}))
    end)

    Application.put_env(:clawdex, :gemini_base_url, "http://localhost:#{bypass.port}/v1beta/models")

    messages = [%{"role" => "user", "content" => "Hello"}]
    opts = [api_key: "test-key", model: "gemini-pro"]

    assert {:error, {:bad_request, %{"error" => "Bad Request"}}} = Gemini.chat(messages, opts)
  end
end
