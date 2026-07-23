defmodule FluxWeb.Plugs.IpAllowlistTest do
  use FluxWeb.ConnCase, async: true

  alias Flux.Security
  alias Flux.Security.Cache

  import Flux.AccountsFixtures

  setup do
    Cache.reset()
    scope = user_scope_fixture()
    %{org_id: scope.organization_id, scope: scope}
  end

  defp run(scope, ip) do
    build_conn()
    |> Plug.Conn.assign(:current_scope, scope)
    |> Map.put(:remote_ip, ip)
    |> FluxWeb.Plugs.IpAllowlist.call([])
  end

  test "passes when the org has no allowlist", %{scope: scope} do
    conn = run(scope, {203, 0, 113, 9})
    refute conn.halted
  end

  test "passes when the client IP is within an allowed range", %{org_id: org_id, scope: scope} do
    {:ok, _} = Security.update_settings(org_id, %{ip_allowlist: ["10.0.0.0/8"]})

    conn = run(scope, {10, 1, 2, 3})
    refute conn.halted
  end

  test "rejects with 403 when the client IP is outside every range", %{
    org_id: org_id,
    scope: scope
  } do
    {:ok, _} = Security.update_settings(org_id, %{ip_allowlist: ["10.0.0.0/8"]})

    conn = run(scope, {192, 168, 1, 1})

    assert conn.halted
    assert conn.status == 403
    assert conn.resp_body =~ "ip_not_allowed"
  end

  test "passes requests with no scope (unauthenticated) untouched" do
    conn =
      build_conn()
      |> Map.put(:remote_ip, {192, 168, 1, 1})
      |> FluxWeb.Plugs.IpAllowlist.call([])

    refute conn.halted
  end
end
