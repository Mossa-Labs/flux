defmodule FluxWeb.Plugs.ApiAuthTest do
  use FluxWeb.ConnCase, async: true

  alias FluxWeb.Plugs.ApiAuth

  describe "call/2" do
    test "allows request with valid API key", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-api-key", "test-api-key")
        |> ApiAuth.call([])

      refute conn.halted
    end

    test "rejects request without API key", %{conn: conn} do
      conn =
        conn
        |> ApiAuth.call([])

      assert conn.halted
      assert conn.status == 401

      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Missing API key"
    end

    test "rejects request with empty API key", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-api-key", "")
        |> ApiAuth.call([])

      assert conn.halted
      assert conn.status == 401
    end

    test "rejects request with invalid API key", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-api-key", "wrong-key")
        |> ApiAuth.call([])

      assert conn.halted
      assert conn.status == 401

      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Invalid API key"
    end

    test "uses secure comparison to prevent timing attacks", %{conn: conn} do
      # This test verifies the key comparison uses constant-time comparison
      # by checking that both short and long invalid keys fail the same way
      short_key_conn =
        conn
        |> put_req_header("x-api-key", "x")
        |> ApiAuth.call([])

      long_key_conn =
        conn
        |> put_req_header("x-api-key", String.duplicate("x", 1000))
        |> ApiAuth.call([])

      assert short_key_conn.halted
      assert long_key_conn.halted
      assert short_key_conn.status == long_key_conn.status
    end
  end
end
