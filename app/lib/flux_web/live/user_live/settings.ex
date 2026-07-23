defmodule FluxWeb.UserLive.Settings do
  @moduledoc "LiveView for user account settings and email management."
  use FluxWeb, :live_view

  on_mount {FluxWeb.UserAuth, :require_sudo_mode}

  alias Flux.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl space-y-4">
      <.header>
        Account Settings
        <:subtitle>Manage your account email address and password settings</:subtitle>
      </.header>

      <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
        <.input
          field={@email_form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          required
        />
        <.button variant="primary" phx-disable-with="Changing...">Change Email</.button>
      </.form>

      <div class="divider" />

      <.form
        for={@password_form}
        id="password_form"
        action={~p"/users/update-password"}
        method="post"
        phx-change="validate_password"
        phx-submit="update_password"
        phx-trigger-action={@trigger_submit}
      >
        <input
          name={@password_form[:email].name}
          type="hidden"
          id="hidden_user_email"
          autocomplete="username"
          value={@current_email}
        />
        <.input
          field={@password_form[:password]}
          type="password"
          label="New password"
          autocomplete="new-password"
          required
        />
        <.input
          field={@password_form[:password_confirmation]}
          type="password"
          label="Confirm new password"
          autocomplete="new-password"
        />
        <.button variant="primary" phx-disable-with="Saving...">
          Save Password
        </.button>
      </.form>

      <div class="divider" />

      <section id="sessions">
        <h2 class="text-lg font-semibold tracking-tight text-base-content">Active sessions</h2>
        <p class="text-sm text-base-content/70 mb-3">
          Devices currently signed in to your account. Revoke any you don't recognize.
        </p>

        <.table id="session-list" rows={@sessions}>
          <:col :let={s} label="Device">
            <span class="font-medium">{device_label(s.user_agent)}</span>
            <span :if={s.token == @current_token} class="badge badge-sm badge-primary ml-1">
              This device
            </span>
          </:col>
          <:col :let={s} label="IP address">{s.ip_address || "—"}</:col>
          <:col :let={s} label="Last active">{format_ts(s.last_active_at || s.inserted_at)}</:col>
          <:col :let={s} label="Signed in">{format_ts(s.inserted_at)}</:col>
          <:action :let={s}>
            <.button
              :if={s.token != @current_token}
              phx-click="revoke_session"
              phx-value-id={s.id}
              data-confirm="Revoke this session?"
              class="btn btn-ghost btn-xs text-error"
            >
              Revoke
            </.button>
          </:action>
        </.table>

        <.button
          :if={length(@sessions) > 1}
          phx-click="revoke_all_other_sessions"
          data-confirm="Sign out all other sessions?"
          class="btn btn-sm mt-3"
        >
          Revoke all other sessions
        </.button>
      </section>

      <div class="divider" />

      <section id="appearance">
        <h2 class="text-lg font-semibold tracking-tight text-base-content">Appearance</h2>
        <p class="text-sm text-base-content/70 mb-3">
          Choose how Flux looks on this device. <span class="font-medium">System</span>
          follows your operating system setting.
        </p>
        <Layouts.theme_toggle />
      </section>
    </div>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:page_title, "Account Settings")
      |> assign(:active_tab, :settings)
      |> assign(:current_token, session["user_token"])
      |> assign_sessions()

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("revoke_session", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    with {int_id, ""} <- Integer.parse(id),
         {:ok, token} <- Accounts.delete_user_session(user, int_id) do
      FluxWeb.UserAuth.disconnect_sessions([token])
      {:noreply, socket |> assign_sessions() |> put_flash(:info, "Session revoked.")}
    else
      _ -> {:noreply, put_flash(socket, :error, "That session could not be found.")}
    end
  end

  def handle_event("revoke_all_other_sessions", _params, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    tokens = Accounts.delete_other_user_sessions(user, socket.assigns.current_token)
    FluxWeb.UserAuth.disconnect_sessions(tokens)

    {:noreply,
     socket |> assign_sessions() |> put_flash(:info, "All other sessions were revoked.")}
  end

  defp assign_sessions(socket) do
    assign(socket, :sessions, Accounts.list_user_sessions(socket.assigns.current_scope.user))
  end

  # Compact, human-friendly label from a raw User-Agent string. Order matters:
  # Chrome/Edge UAs also contain "Safari", so check the more specific tokens first.
  defp device_label(nil), do: "Unknown device"

  defp device_label(ua) when is_binary(ua) do
    browser =
      cond do
        String.contains?(ua, "Edg") -> "Edge"
        String.contains?(ua, "Chrome") -> "Chrome"
        String.contains?(ua, "Firefox") -> "Firefox"
        String.contains?(ua, "Safari") -> "Safari"
        true -> "Browser"
      end

    os =
      cond do
        String.contains?(ua, "iPhone") or String.contains?(ua, "iPad") -> "iOS"
        String.contains?(ua, "Android") -> "Android"
        String.contains?(ua, "Mac OS") -> "macOS"
        String.contains?(ua, "Windows") -> "Windows"
        String.contains?(ua, "Linux") -> "Linux"
        true -> "unknown OS"
      end

    "#{browser} · #{os}"
  end

  defp format_ts(nil), do: "—"
  defp format_ts(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
end
