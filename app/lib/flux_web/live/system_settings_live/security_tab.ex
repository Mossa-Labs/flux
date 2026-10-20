defmodule FluxWeb.SystemSettingsLive.SecurityTab do
  @moduledoc """
  IP allowlist, session timeout, password policy and MFA enforcement for System Settings.
  """
  use FluxWeb, :html

  alias FluxWeb.Components.UpgradePrompt

  attr :form, :any, required: true
  attr :error, :string, default: nil
  attr :password_policy_enabled, :boolean, default: false
  attr :mfa_enforcement_enabled, :boolean, default: false

  def security_section(assigns) do
    ~H"""
    <section class="card bg-base-100 shadow-sm border border-base-200">
      <div class="card-body">
        <h2 class="card-title text-base font-bold">
          <.icon name="hero-shield-check" class="w-5 h-5" /> IP Allowlist
        </h2>
        <p class="text-sm text-base-content/60">
          Restrict <span class="font-semibold">API</span>
          access to specific networks. One CIDR range per line
          (e.g. <code>203.0.113.0/24</code>
          or <code>198.51.100.7</code>). Leave empty to allow all
          IPs. Applies to the whole API, including inbound webhooks — this does
          <span class="font-semibold">not</span>
          restrict this settings UI, so you cannot lock yourself out.
        </p>

        <.form
          for={@form}
          id="ip-allowlist-form"
          phx-submit="save_security_settings"
          class="mt-4 space-y-2"
        >
          <.input
            field={@form[:ip_allowlist]}
            type="textarea"
            rows="4"
            placeholder="203.0.113.0/24\n198.51.100.7"
            class="font-mono"
          />
          <p :if={@error} class="text-sm text-error" id="ip-allowlist-error">{@error}</p>
          <.button class="btn btn-primary btn-sm">Save allowlist</.button>
        </.form>

        <div class="divider my-2"></div>

        <h3 class="font-semibold text-sm">Session timeout</h3>
        <p class="text-sm text-base-content/60">
          Sign members out of the web app after this period of inactivity.
        </p>

        <.form
          for={@form}
          id="session-timeout-form"
          phx-submit="save_session_timeout"
          class="mt-2 flex flex-col sm:flex-row gap-2 sm:items-end"
        >
          <.input
            field={@form[:session_timeout_minutes]}
            type="select"
            label="Idle timeout"
            options={session_timeout_options()}
          />
          <.button class="btn btn-primary btn-sm">Save timeout</.button>
        </.form>

        <div class="divider my-2"></div>

        <h3 class="font-semibold text-sm">
          <.icon name="hero-key" class="w-4 h-4" /> Password policy
        </h3>
        <p class="text-sm text-base-content/60">
          Strengthen the rules new passwords must satisfy, on top of the built-in
          12-character minimum. Optionally require members to rotate their password
          on a schedule.
        </p>

        <%= if @password_policy_enabled do %>
          <.form
            for={@form}
            id="password-policy-form"
            phx-submit="save_password_policy"
            class="mt-2 space-y-3"
          >
            <div class="flex flex-col sm:flex-row gap-2 sm:items-end">
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

            <fieldset class="flex flex-col gap-1">
              <legend class="text-sm font-medium">Require at least one…</legend>
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
              <.input
                field={@form[:password_require_number]}
                type="checkbox"
                label="Number (0–9)"
              />
              <.input
                field={@form[:password_require_special]}
                type="checkbox"
                label="Special character (!?@#$…)"
              />
            </fieldset>

            <.button class="btn btn-primary btn-sm">Save password policy</.button>
          </.form>
        <% else %>
          <div class="mt-2">
            <UpgradePrompt.upgrade_prompt feature={:password_policy} size={:compact} />
          </div>
        <% end %>
      </div>

      <div class="mt-6">
        <h3 class="text-sm font-semibold">Require two-factor authentication</h3>
        <p class="text-sm text-base-content/70">
          Require every member of this organization to enable two-factor
          authentication. Members without it are prompted to enroll before they can
          continue. Members set up their own authenticator under Account Settings.
        </p>

        <%= if @mfa_enforcement_enabled do %>
          <.form
            for={@form}
            id="mfa-enforcement-form"
            phx-submit="save_mfa_enforcement"
            class="mt-2 space-y-3"
          >
            <.input
              field={@form[:require_mfa]}
              type="checkbox"
              label="Require MFA for all members"
            />
            <.button class="btn btn-primary btn-sm">Save</.button>
          </.form>
        <% else %>
          <div class="mt-2">
            <UpgradePrompt.upgrade_prompt feature={:mfa_enforcement} size={:compact} />
          </div>
        <% end %>
      </div>
    </section>
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
