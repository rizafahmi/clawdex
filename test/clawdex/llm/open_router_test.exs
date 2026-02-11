defmodule Clawdex.LLM.OpenRouterTest do
  use ExUnit.Case, async: true

  alias Clawdex.LLM.OpenRouter

  @opts [api_key: "test-key", model: "anthropic/claude-sonnet-4-20250514"]

  describe "chat/2" do
    test "sends messages and returns response text" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["model"] == "anthropic/claude-sonnet-4-20250514"
        assert length(decoded["messages"]) == 1

        resp = %{
          "choices" => [
            %{"message" => %{"role" => "assistant", "content" => "Hello!"}}
          ]
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(resp))
      end)

      messages = [%{"role" => "user", "content" => "Hi"}]
      opts = @opts ++ [base_url: "http://localhost:#{bypass.port}"]
      assert {:ok, "Hello!"} = OpenRouter.chat(messages, opts)
    end

    test "prepends system message when system prompt provided" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        [system_msg | _rest] = decoded["messages"]
        assert system_msg["role"] == "system"
        assert system_msg["content"] == "Be helpful"

        resp = %{
          "choices" => [
            %{"message" => %{"role" => "assistant", "content" => "Sure!"}}
          ]
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(resp))
      end)

      messages = [%{"role" => "user", "content" => "Hi"}]
      opts = @opts ++ [system: "Be helpful", base_url: "http://localhost:#{bypass.port}"]
      assert {:ok, "Sure!"} = OpenRouter.chat(messages, opts)
    end

    test "returns error on 401" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
        Plug.Conn.resp(conn, 401, ~s({"error": "unauthorized"}))
      end)

      messages = [%{"role" => "user", "content" => "Hi"}]
      opts = @opts ++ [base_url: "http://localhost:#{bypass.port}"]
      assert {:error, :invalid_api_key} = OpenRouter.chat(messages, opts)
    end

    test "returns error on 429" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
        Plug.Conn.resp(conn, 429, ~s({"error": "rate limited"}))
      end)

      messages = [%{"role" => "user", "content" => "Hi"}]
      opts = @opts ++ [base_url: "http://localhost:#{bypass.port}"]
      assert {:error, :rate_limited} = OpenRouter.chat(messages, opts)
    end
  end
end
