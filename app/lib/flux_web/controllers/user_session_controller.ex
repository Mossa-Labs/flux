defmodule FluxWeb.UserSessionController do
  @moduledoc "Controller for user session creation (login) and deletion (logout)."
  use FluxWeb, :controller

  alias Flux.Accounts
  alias Flux.Accounts.Scope
  alias FluxWeb.UserAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, "User confirmed successfully.")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  # magic link login
  defp create(conn, %{"user" => %{"token" => _token} = user_params}, info) do
    {:ok, strategy} = Flux.Auth.Registry.lookup(:magic_link)

    case strategy.authenticate(user_params) do
      {:ok, {user, tokens_to_disconnect}} ->
        if Scope.user_can_log_in?(user) do
          UserAuth.disconnect_sessions(tokens_to_disconnect)
          log_in_or_challenge(conn, user, user_params, info)
        else
          conn
          |> put_flash(:error, "Your account has been disabled. Contact your administrator.")
          |> redirect(to: ~p"/users/log-in")
        end

      _ ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # email + password login
  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email} = user_params
    {:ok, strategy} = Flux.Auth.Registry.lookup(:password)

    case strategy.authenticate(user_params) do
      {:ok, user} ->
        if Scope.user_can_log_in?(user) do
          log_in_or_challenge(conn, user, user_params, info)
        else
          conn
          |> put_flash(:error, "Your account has been disabled. Contact your administrator.")
          |> put_flash(:email, String.slice(email, 0, 160))
          |> redirect(to: ~p"/users/log-in")
        end

      {:error, _} ->
        Flux.Audit.log(%{
          action: :failed_login,
          actor_type: :system,
          resource_type: :user,
          metadata:
            Map.put(FluxWeb.AuditMeta.from_conn(conn), "email", String.slice(email, 0, 160))
        })

        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> put_flash(:error, "Invalid email or password")
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # Second-factor verification. The pending user was stashed in the (signed)
  # session by log_in_or_challenge/4; the code is re-verified here — the challenge
  # LiveView is only UX and is never trusted to establish the session.
  def verify_totp(conn, %{"totp" => %{"code" => code}}) do
    pending_id = get_session(conn, :mfa_pending_user_id)
    pending_at = get_session(conn, :mfa_pending_at)
    user = pending_id && Accounts.get_user(pending_id)

    cond do
      is_nil(user) or mfa_challenge_expired?(pending_at) ->
        conn
        |> clear_mfa_pending()
        |> put_flash(:error, "Your login request expired. Please sign in again.")
        |> redirect(to: ~p"/users/log-in")

      verify_second_factor(user, code) ->
        remember_me = get_session(conn, :mfa_pending_remember_me)

        conn
        |> clear_mfa_pending()
        |> put_flash(:info, "Welcome back!")
        |> UserAuth.log_in_user(user, %{"remember_me" => to_string(remember_me == true)})

      true ->
        Flux.Audit.log(%{
          action: :failed_login,
          actor_type: :system,
          resource_type: :user,
          resource_id: user.id,
          metadata: Map.put(FluxWeb.AuditMeta.from_conn(conn), "reason", "invalid_mfa_code")
        })

        conn
        |> put_flash(:error, "That code was invalid. Please try again.")
        |> redirect(to: ~p"/users/two-factor")
    end
  end

  def verify_totp(conn, _params) do
    conn
    |> put_flash(:error, "Enter your authentication code.")
    |> redirect(to: ~p"/users/two-factor")
  end

  # Login is complete unless the user has MFA enabled, in which case we stash a
  # short-lived pending reference and divert to the second-factor challenge. The
  # full session is only minted (via UserAuth.log_in_user/3) once the code passes.
  defp log_in_or_challenge(conn, user, user_params, info) do
    if Accounts.mfa_enabled?(user) do
      conn
      |> put_session(:mfa_pending_user_id, user.id)
      |> put_session(:mfa_pending_at, System.system_time(:second))
      |> put_session(:mfa_pending_remember_me, user_params["remember_me"] == "true")
      |> redirect(to: ~p"/users/two-factor")
    else
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    end
  end

  # Accepts a 6-digit TOTP code or a single-use backup code (consumed on use).
  defp verify_second_factor(user, code) when is_binary(code) do
    code = String.trim(code)
    Accounts.verify_totp(user, code) or Accounts.verify_backup_code(user, code) == :ok
  end

  defp verify_second_factor(_user, _code), do: false

  # The challenge is valid for 10 minutes after the first factor succeeds.
  @mfa_challenge_ttl_seconds 600
  defp mfa_challenge_expired?(nil), do: true

  defp mfa_challenge_expired?(at) when is_integer(at) do
    System.system_time(:second) - at > @mfa_challenge_ttl_seconds
  end

  defp clear_mfa_pending(conn) do
    conn
    |> delete_session(:mfa_pending_user_id)
    |> delete_session(:mfa_pending_at)
    |> delete_session(:mfa_pending_remember_me)
  end

  def update_password(conn, %{"user" => user_params} = params) do
    scope = conn.assigns.current_scope
    user = scope.user
    true = Accounts.sudo_mode?(user)

    {:ok, {_user, expired_tokens}} =
      Accounts.update_user_password(user, user_params, org_id: scope.organization_id)

    # disconnect all existing LiveViews with old sessions
    UserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Password updated successfully!")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
