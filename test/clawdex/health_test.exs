defmodule Clawdex.HealthTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias Clawdex.Health

  @opts Health.init([])

  test "GET /health returns 200 and json status" do
    # Create a test connection
    conn = conn(:get, "/health")

    # Invoke the plug
    conn = Health.call(conn, @opts)

    # Assert the response
    assert conn.state == :sent
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

    body = Jason.decode!(conn.resp_body)
    assert body["status"] == "ok"
    assert is_integer(body["sessions"])
  end

  test "GET /unknown returns 404" do
    conn = conn(:get, "/unknown")
    conn = Health.call(conn, @opts)

    assert conn.status == 404
    assert conn.resp_body == "not found"
  end
end
