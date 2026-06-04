defmodule FluxWeb.API.HealthControllerTest do
  use FluxWeb.ConnCase, async: true

  test "returns 200 with status ok and no auth required", %{conn: conn} do
    body = conn |> get(~p"/health") |> json_response(200)

    assert body["status"] == "ok"
    assert body["database"] == "connected"
    assert body["queue"] == "connected"
    assert is_binary(body["version"])
  end
end
