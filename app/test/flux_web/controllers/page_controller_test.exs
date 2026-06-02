defmodule FluxWeb.PageControllerTest do
  use FluxWeb.ConnCase

  test "GET / redirects unauthenticated users to login", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/users/log-in"
  end

  test "GET / redirects authenticated users to dashboard", %{conn: conn} do
    conn = conn |> log_in_user(Flux.AccountsFixtures.user_fixture()) |> get(~p"/")
    assert redirected_to(conn) == ~p"/dashboard"
  end
end
