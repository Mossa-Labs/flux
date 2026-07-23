defmodule FluxWeb.UserLive.TotpChallenge do
  @moduledoc """
  Second-factor (TOTP) challenge shown between password/magic-link auth and a full
  session (MOS-591).

  The pending user is held in the signed session by
  `FluxWeb.UserSessionController.log_in_or_challenge/4`. This page only renders the
  code form; the submitted code is verified server-side by
  `FluxWeb.UserSessionController.verify_totp/2`, which is the sole place a session is
  minted — this LiveView is never trusted to establish login.
  """
  use FluxWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            <p>Two-factor authentication</p>
            <:subtitle>
              Enter the 6-digit code from your authenticator app. Lost your device?
              Enter one of your backup codes instead.
            </:subtitle>
          </.header>
        </div>

        <.form for={@form} id="totp_form" action={~p"/users/two-factor"} method="post">
          <.input
            field={@form[:code]}
            type="text"
            label="Authentication code"
            autocomplete="one-time-code"
            inputmode="text"
            phx-mounted={JS.focus()}
            required
          />
          <.button class="btn btn-primary w-full">
            Verify <span aria-hidden="true">→</span>
          </.button>
        </.form>

        <p class="text-center text-sm">
          <.link
            href={~p"/users/log-out"}
            method="delete"
            class="text-base-content/70 hover:underline"
          >
            Cancel and sign out
          </.link>
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    # No pending login → nothing to challenge. Send the visitor back to log in.
    if session["mfa_pending_user_id"] do
      {:ok,
       assign(socket, form: to_form(%{}, as: "totp"), page_title: "Two-factor authentication")}
    else
      {:ok, push_navigate(socket, to: ~p"/users/log-in")}
    end
  end
end
