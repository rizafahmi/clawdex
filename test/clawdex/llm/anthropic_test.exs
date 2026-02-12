defmodule Clawdex.LLM.AnthropicTest do
  use ExUnit.Case, async: true

  alias Clawdex.LLM.Anthropic

  @opts [api_key: "test-key", model: "claude-sonnet-4-20250514"]

  describe "chat/2" do
    test "sends messages and returns response text" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "POST", "/messages", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["model"] == "claude-sonnet-4-20250514"
        assert decoded["max_tokens"] == 8192
        assert length(decoded["messages"]) == 1
        refute Map.has_key?(decoded, "system")

        assert Plug.Conn.get_req_header(conn, "x-api-key") == ["test-key"]
        assert Plug.Conn.get_req_header(conn, "anthropic-version") == ["2023-06-01"]

        resp = %{
          "content" => [%{"type" => "text", "text" => "Hello!"}],
          "role" => "assistant"
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(resp))
      end)

      messages = [%{"role" => "user", "content" => "Hi"}]
      opts = @opts ++ [base_url: "http://localhost:#{bypass.port}"]
      assert {:ok, "Hello!"} = Anthropic.chat(messages, opts)
    end

    test "includes system prompt as top-level field" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "POST", "/messages", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["system"] == "Be helpful"

        resp = %{
          "content" => [%{"type" => "text", "text" => "Sure!"}],
          "role" => "assistant"
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(resp))
      end)

      messages = [%{"role" => "user", "content" => "Hi"}]
      opts = @opts ++ [system: "Be helpful", base_url: "http://localhost:#{bypass.port}"]
      assert {:ok, "Sure!"} = Anthropic.chat(messages, opts)
    end

    test "strips anthropic/ prefix from model name" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "POST", "/messages", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["model"] == "claude-sonnet-4-20250514"

        resp = %{
          "content" => [%{"type" => "text", "text" => "OK"}],
          "role" => "assistant"
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(resp))
      end)

      messages = [%{"role" => "user", "content" => "Hi"}]

      opts = [
        api_key: "test-key",
        model: "anthropic/claude-sonnet-4-20250514",
        base_url: "http://localhost:#{bypass.port}"
      ]

      assert {:ok, "OK"} = Anthropic.chat(messages, opts)
    end

    test "returns error on 401" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "POST", "/messages", fn conn ->
        Plug.Conn.resp(conn, 401, ~s({"error": "unauthorized"}))
      end)

      messages = [%{"role" => "user", "content" => "Hi"}]
      opts = @opts ++ [base_url: "http://localhost:#{bypass.port}"]
      assert {:error, :invalid_api_key} = Anthropic.chat(messages, opts)
    end

    test "returns error on 429" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "POST", "/messages", fn conn ->
        Plug.Conn.resp(conn, 429, ~s({"error": "rate limited"}))
      end)

      messages = [%{"role" => "user", "content" => "Hi"}]
      opts = @opts ++ [base_url: "http://localhost:#{bypass.port}"]
      assert {:error, :rate_limited} = Anthropic.chat(messages, opts)
    end

    test "handles multiple content blocks" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "POST", "/messages", fn conn ->
        resp = %{
          "content" => [
            %{"type" => "text", "text" => "Part 1 "},
            %{"type" => "image", "source" => "..."},
            %{"type" => "text", "text" => "Part 2"}
          ],
          "role" => "assistant"
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(resp))
      end)

      messages = [%{"role" => "user", "content" => "Hi"}]
      opts = @opts ++ [base_url: "http://localhost:#{bypass.port}"]
      assert {:ok, "Part 1 Part 2"} = Anthropic.chat(messages, opts)
    end
  end
end
