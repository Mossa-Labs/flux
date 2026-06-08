defmodule FluxWeb.API.HealthControllerTest do
  use FluxWeb.ConnCase, async: true

  test "returns 200 with status ok and no auth required", %{conn: conn} do
    body = conn |> get(~p"/health") |> json_response(200)

    assert body["status"] == "ok"
    assert body["database"] == "connected"
    assert body["queue"] == "connected"
    assert is_binary(body["version"])
  end

  test "reports cluster membership", %{conn: conn} do
    body = conn |> get(~p"/health") |> json_response(200)

    cluster = body["cluster"]
    assert cluster["node"] == to_string(node())
    assert cluster["node_count"] >= 1
    assert to_string(node()) in cluster["nodes"]
    assert cluster["supervisor_members"] >= 1
  end
end
