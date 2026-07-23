defmodule FluxWeb.UserAuthPasswordRotationTest do
  # async: false — swaps the globally-registered active password policy provider.
  use FluxWeb.ConnCase, async: false

  alias Flux.Accounts
  alias Flux.Accounts.PasswordPolicy.Registry
  alias FluxWeb.UserAuth

  import Flux.AccountsFixtures

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, FluxWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    previous = Registry.active()
    Registry.set_active(Flux.PasswordPolicyTestProvider)
    Application.put_env(:flux, :test_password_policy, expired: true)

    on_exit(fn ->
      Registry.set_active(previous)
      Application.delete_env(:flux, :test_password_policy)
    end)

    %{conn: conn, user: user_fixture()}
  end

  describe "password rotation at login (MOS-590)" do
    test "redirects to settings when the rotation policy has lapsed", %{conn: conn, user: user} do
      token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> Phoenix.Controller.fetch_flash([])
        |> Map.put(:request_path, "/dashboard")
        |> put_session(:user_token, token)
        |> UserAuth.fetch_current_scope_for_user([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/users/settings"
      # The session survives — the user must rotate, not re-login.
      assert Accounts.get_user_by_session_token(token)
    end

    test "does not force rotation while already on an escape path", %{conn: conn, user: user} do
      token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> Phoenix.Controller.fetch_flash([])
        |> Map.put(:request_path, "/users/settings")
        |> put_session(:user_token, token)
        |> UserAuth.fetch_current_scope_for_user([])

      refute conn.halted
      assert conn.assigns.current_scope.user.id == user.id
    end
  end
end
