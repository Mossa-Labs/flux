defmodule FluxWeb.SystemSettingsLive.SecurityTab do
  @moduledoc """
  The Security tab of System Settings: IP allowlist, session timeout, password
  policy and MFA enforcement, one card each.
  """
  use FluxWeb, :html

  import FluxWeb.SystemSettingsLive.Components

  alias FluxWeb.Components.UpgradePrompt

  # All four forms share one form struct (`as: :security`); each submits only
  # its own fields and its own event.
  attr :form, :any, required: true
  attr :error, :string, default: nil
  attr :password_policy_enabled, :boolean, default: false
  attr :mfa_enforcement_enabled, :boolean, default: false

  def security_tab(assigns) do
    ~H"""
    <div class="grid gap-6 lg:grid-cols-2">
      <.settings_card id="ip-allowlist-card" title="IP allowlist" icon="hero-globe-alt">
        <:description>
          Restrict <span class="font-semibold">API</span>
          access to specific networks. One CIDR range per line
          (e.g. <code class="font-mono text-xs">203.0.113.0/24</code>
          or <code class="font-mono text-xs">198.51.100.7</code>). Leave empty to allow all
          IPs. Applies to the whole API, including inbound webhooks — this does
          <span class="font-semibold">not</span>
          restrict this settings UI, so you cannot lock yourself out.
        </:description>

        <.form
          for={@form}
          id="ip-allowlist-form"
          phx-submit="save_security_settings"
          class="space-y-2"
        >
          <.input
            field={@form[:ip_allowlist]}
            type="textarea"
            rows="4"
            aria-label="Allowed CIDR ranges"
            placeholder="203.0.113.0/24\n198.51.100.7"
            class="textarea w-full font-mono text-sm"
          />
          <p :if={@error} class="text-sm text-error" id="ip-allowlist-error">{@error}</p>
          <.button class="btn btn-primary btn-sm">Save allowlist</.button>
        </.form>
      </.settings_card>

      <.settings_card id="session-timeout-card" title="Session timeout" icon="hero-clock">
        <:description>
          Sign members out of the web app after this period of inactivity.
        </:description>

        <.form
          for={@form}
          id="session-timeout-form"
          phx-submit="save_session_timeout"
          class="flex flex-col gap-x-2 sm:flex-row sm:items-end"
        >
          <div class="sm:min-w-48">
            <.input
              field={@form[:session_timeout_minutes]}
              type="select"
              label="Idle timeout"
              options={session_timeout_options()}
            />
          </div>
          <div class="mb-2">
            <.button class="btn btn-primary btn-sm">Save timeout</.button>
          </div>
        </.form>
      </.settings_card>

      <.settings_card id="password-policy-card" title="Password policy" icon="hero-lock-closed">
        <:description>
          Strengthen the rules new passwords must satisfy, on top of the built-in
          12-character minimum. Optionally require members to rotate their password
          on a schedule.
        </:description>

        <%= if @password_policy_enabled do %>
          <.form
            for={@form}
            id="password-policy-form"
            phx-submit="save_password_policy"
            class="space-y-3"
          >
            <div class="grid gap-x-3 sm:grid-cols-2">
              <.input
                field={@form[:password_min_length]}
                type="number"
                min="12"
                max="128"
                label="Minimum length"
              />
              <.input
                field={@form[:password_rotation_days]}
                type="number"
                min="1"
                label="Rotate every (days)"
                placeholder="Never"
              />
            </div>

            <fieldset class="grid gap-x-4 sm:grid-cols-2">
              <legend class="mb-1 text-sm font-medium">Require at least one…</legend>
              <.input
                field={@form[:password_require_upper]}
                type="checkbox"
                label="Uppercase letter (A–Z)"
              />
              <.input
                field={@form[:password_require_lower]}
                type="checkbox"
                label="Lowercase letter (a–z)"
              />
              <.input field={@form[:password_require_number]} type="checkbox" label="Number (0–9)" />
              <.input
                field={@form[:password_require_special]}
                type="checkbox"
                label="Special character (!?@#$…)"
              />
            </fieldset>

            <.button class="btn btn-primary btn-sm">Save password policy</.button>
          </.form>
        <% else %>
          <UpgradePrompt.upgrade_prompt feature={:password_policy} size={:compact} />
        <% end %>
      </.settings_card>

      <.settings_card id="mfa-card" title="Two-factor authentication" icon="hero-device-phone-mobile">
        <:description>
          Require every member of this organization to enable two-factor
          authentication. Members without it are prompted to enroll before they can
          continue. Members set up their own authenticator under Account Settings.
        </:description>

        <%= if @mfa_enforcement_enabled do %>
          <.form
            for={@form}
            id="mfa-enforcement-form"
            phx-submit="save_mfa_enforcement"
            class="space-y-3"
          >
            <div class="rounded-box border border-base-content/5 bg-base-300 px-4 pt-3 pb-1">
              <.input field={@form[:require_mfa]} type="checkbox" label="Require MFA for all members" />
            </div>
            <.button class="btn btn-primary btn-sm">Save</.button>
          </.form>
        <% else %>
          <UpgradePrompt.upgrade_prompt feature={:mfa_enforcement} size={:compact} />
        <% end %>
      </.settings_card>
    </div>
    """
  end

  # Preset idle-session-timeout options ({label, minutes-as-string}). The stored
  # minimum is 1 hour (enforced by the SecuritySettings changeset).
  defp session_timeout_options do
    [
      {"1 hour", "60"},
      {"8 hours", "480"},
      {"1 day", "1440"},
      {"7 days", "10080"},
      {"30 days", "43200"},
      {"90 days", "129600"}
    ]
  end
end
