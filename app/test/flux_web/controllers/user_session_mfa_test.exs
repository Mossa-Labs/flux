defmodule FluxWeb.UserSessionMfaTest do
  @moduledoc "Login second-factor (TOTP) interception (MOS-591)."
  use FluxWeb.ConnCase, async: true

  import Flux.AccountsFixtures

  alias Flux.Accounts.Mfa

  # Enrolls the user in MFA and returns {user, secret, backup_codes}.
  defp enroll_mfa(user) do
    %{secret: secret} = Mfa.start_enrollment(user)
    {:ok, codes} = Mfa.confirm_enrollment(user, secret, NimbleTOTP.verification_code(secret))
    {secret, codes}
  end

  defp log_in_with_password(conn, user) do
    post(conn, ~p"/users/log-in", %{
      "user" => %{"email" => user.email, "password" => valid_user_password()}
    })
  end

  describe "POST /users/log-in with MFA enabled" do
    setup do
      user = set_password(user_fixture())
      {secret, codes} = enroll_mfa(user)
      %{user: user, secret: secret, backup_codes: codes}
    end

    test "diverts to the two-factor challenge instead of logging in", %{conn: conn, user: user} do
      conn = log_in_with_password(conn, user)

      assert redirected_to(conn) == ~p"/users/two-factor"
      # No full session yet — the second factor hasn't been provided.
      refute get_session(conn, :user_token)
      assert get_session(conn, :mfa_pending_user_id) == user.id
    end
  end

  describe "POST /users/two-factor" do
    setup %{conn: conn} do
      user = set_password(user_fixture())
      {secret, codes} = enroll_mfa(user)
      conn = log_in_with_password(conn, user)
      %{conn: conn, user: user, secret: secret, backup_codes: codes}
    end

    test "completes login with a valid TOTP code", %{conn: conn, secret: secret} do
      conn =
        post(conn, ~p"/users/two-factor", %{
          "totp" => %{"code" => NimbleTOTP.verification_code(secret)}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :mfa_pending_user_id)
    end

    test "completes login with a backup code (single use)", %{
      conn: conn,
      backup_codes: [code | _]
    } do
      conn = post(conn, ~p"/users/two-factor", %{"totp" => %{"code" => code}})

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
    end

    test "rejects an invalid code and stays on the challenge", %{conn: conn} do
      conn = post(conn, ~p"/users/two-factor", %{"totp" => %{"code" => "000000"}})

      assert redirected_to(conn) == ~p"/users/two-factor"
      refute get_session(conn, :user_token)
      assert get_session(conn, :mfa_pending_user_id)
    end
  end

  describe "GET /users/two-factor" do
    test "redirects to log-in when there is no pending login", %{conn: conn} do
      conn = get(conn, ~p"/users/two-factor")
      # The LiveView bounces an unpending visitor back to the login page.
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end
end
