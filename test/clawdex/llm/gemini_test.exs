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
      |> Plug.Conn.resp(
        200,
        Jason.encode!(%{
          "candidates" => [
            %{
              "content" => %{
                "parts" => [%{"text" => "Hello from Gemini"}]
              }
            }
          ]
        })
      )
    end)

    base_url = "http://localhost:#{bypass.port}/v1beta/models"
    messages = [%{"role" => "user", "content" => "Hello Gemini"}]
    opts = [api_key: "test-key", model: "gemini-pro", base_url: base_url]

    assert {:ok, "Hello from Gemini"} = Gemini.chat(messages, opts)
  end

  test "handles safety blockage", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1beta/models/gemini-pro:generateContent", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(
        200,
        Jason.encode!(%{
          "candidates" => [
            %{"finishReason" => "SAFETY"}
          ]
        })
      )
    end)

    base_url = "http://localhost:#{bypass.port}/v1beta/models"
    messages = [%{"role" => "user", "content" => "Unsafe content"}]
    opts = [api_key: "test-key", model: "gemini-pro", base_url: base_url]

    assert {:ok, "[Response blocked due to safety settings]"} = Gemini.chat(messages, opts)
  end

  test "handles API errors", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1beta/models/gemini-pro:generateContent", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(400, Jason.encode!(%{"error" => "Bad Request"}))
    end)

    base_url = "http://localhost:#{bypass.port}/v1beta/models"
    messages = [%{"role" => "user", "content" => "Hello"}]
    opts = [api_key: "test-key", model: "gemini-pro", base_url: base_url]

    assert {:error, {:bad_request, %{"error" => "Bad Request"}}} = Gemini.chat(messages, opts)
  end

  test "includes system instruction", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1beta/models/gemini-pro:generateContent", fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      decoded_body = Jason.decode!(body)

      assert get_in(decoded_body, ["systemInstruction", "parts", Access.at(0), "text"]) ==
               "Be helpful"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(
        200,
        Jason.encode!(%{
          "candidates" => [
            %{
              "content" => %{
                "parts" => [%{"text" => "OK"}]
              }
            }
          ]
        })
      )
    end)

    base_url = "http://localhost:#{bypass.port}/v1beta/models"
    messages = [%{"role" => "user", "content" => "Hello"}]
    opts = [api_key: "test-key", model: "gemini-pro", system: "Be helpful", base_url: base_url]

    assert {:ok, "OK"} = Gemini.chat(messages, opts)
  end

  test "handles multiple parts in response", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1beta/models/gemini-pro:generateContent", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(
        200,
        Jason.encode!(%{
          "candidates" => [
            %{
              "content" => %{
                "parts" => [
                  %{"text" => "Part 1 "},
                  %{"text" => "Part 2"}
                ]
              }
            }
          ]
        })
      )
    end)

    base_url = "http://localhost:#{bypass.port}/v1beta/models"
    messages = [%{"role" => "user", "content" => "Hello"}]
    opts = [api_key: "test-key", model: "gemini-pro", base_url: base_url]

    assert {:ok, "Part 1 Part 2"} = Gemini.chat(messages, opts)
  end
end
