defmodule FluxWeb.SystemSettingsLive.SSOTab do
  @moduledoc """
  The Single sign-on tab of System Settings.

  Laid out in the order an organization adopts SSO, which is usually long after
  it started with passwords:

    1. **Identity provider**: paste the IdP's metadata and map its attributes.
    2. **Domains**: claim the email domains it vouches for and prove it with DNS.
    3. **Readiness**: watch members link their accounts on first SSO sign-in.
    4. **Enforcement**: require SSO, once enough of them have.

  Nothing is enforced until step 4. Until then SSO is an extra way in and
  passwords keep working.
  """
  use FluxWeb, :html

  import FluxWeb.SystemSettingsLive.Components

  alias Flux.Auth.SSO.{Config, Domain}
  alias FluxWeb.Components.UpgradePrompt

  # Custom Tailwind rather than daisyUI component classes (see CLAUDE.md). Theme
  # colour tokens (base-content, primary, …) keep it in step with light/dark.
  @code_textarea "w-full rounded-lg border border-base-content/20 bg-base-100 px-3 py-2 font-mono text-xs leading-relaxed transition-colors focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/30"
  @quiet_button "inline-flex items-center gap-1 rounded-lg px-2.5 py-1.5 text-xs font-medium text-base-content/70 transition-colors hover:bg-base-content/10 hover:text-base-content focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/40"
  @danger_quiet_button "inline-flex items-center gap-1 rounded-lg px-2.5 py-1.5 text-xs font-medium text-error transition-colors hover:bg-error/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-error/40"
  @danger_button "inline-flex items-center justify-center rounded-lg bg-error px-4 py-2 text-sm font-semibold text-error-content shadow-sm transition-colors hover:bg-error/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-error/40"

  attr :enabled, :boolean, required: true
  attr :config, :any, default: nil, doc: "a Flux.Auth.SSO.Config or nil"
  attr :form, :any, required: true
  attr :domain_form, :any, required: true
  attr :base_url, :string, required: true
  attr :rbac_mode, :atom, required: true
  attr :teams, :list, default: []
  attr :readiness, :map, required: true, doc: "%{total, linked} for non-owner members"
  attr :streams, :any, required: true
  attr :confirm, :atom, default: nil, doc: "nil | :enforce | :delete"

  def sso_tab(assigns) do
    ~H"""
    <%= if @enabled do %>
      <div class="space-y-6">
        <.status_strip config={@config} readiness={@readiness} />

        <div class="grid gap-6 lg:grid-cols-5">
          <.settings_card
            id="sso-idp-card"
            title="Identity provider"
            icon="hero-building-office-2"
            class="lg:col-span-3"
          >
            <:description>
              Paste the SAML metadata XML from Okta, Microsoft Entra ID (Azure AD),
              Google Workspace or any SAML 2.0 identity provider. Saving changes
              nothing for members until a domain is verified.
            </:description>
            <:actions>
              <button
                :if={@config}
                type="button"
                id="sso-delete-button"
                phx-click="confirm_sso_delete"
                class={danger_quiet_button()}
              >
                <.icon name="hero-trash" class="size-4" /> Remove
              </button>
            </:actions>

            <.form for={@form} id="sso-config-form" phx-submit="save_sso_config" class="space-y-4">
              <.input
                field={@form[:idp_metadata]}
                type="textarea"
                rows="6"
                label="IdP metadata XML"
                placeholder="Paste the EntityDescriptor XML from your identity provider"
                class={code_textarea()}
                error_class="border-error"
              />

              <fieldset class="space-y-1">
                <legend class="text-sm font-medium">Attribute names</legend>
                <p class="text-xs text-base-content/60">
                  The names your IdP sends. Leave email blank to use the subject (NameID).
                </p>
                <div class="grid gap-x-3 sm:grid-cols-2">
                  <.input
                    field={@form[:email_attribute]}
                    type="text"
                    label="Email"
                    placeholder="email"
                  />
                  <.input
                    field={@form[:groups_attribute]}
                    type="text"
                    label="Groups"
                    placeholder="groups"
                  />
                  <.input
                    field={@form[:first_name_attribute]}
                    type="text"
                    label="First name"
                    placeholder="firstName"
                  />
                  <.input
                    field={@form[:last_name_attribute]}
                    type="text"
                    label="Last name"
                    placeholder="lastName"
                  />
                </div>
              </fieldset>

              <div class="grid gap-x-3 sm:grid-cols-2">
                <.input
                  field={@form[:role_mapping]}
                  type="textarea"
                  rows="3"
                  label="Group → role"
                  placeholder="Flux Admins = admin\nData Eng = member"
                  class={code_textarea()}
                  error_class="border-error"
                />
                <div>
                  <.input
                    field={@form[:default_role]}
                    type="select"
                    label="Role for new users no group maps"
                    options={role_options()}
                  />
                  <.input
                    :if={@rbac_mode == :team_centric}
                    field={@form[:default_team_id]}
                    type="select"
                    label="Team new users join"
                    options={team_options(@teams)}
                  />
                </div>
              </div>
              <p class="text-xs text-base-content/60">
                One mapping per line; the first matching group wins. Roles re-sync on
                each SSO sign-in when a group matches. A role set by hand is kept
                when none does, and SSO never changes an owner.
              </p>

              <.button variant="primary" phx-disable-with="Saving…">
                {if @config, do: "Save identity provider", else: "Set up SSO"}
              </.button>
            </.form>
          </.settings_card>

          <.settings_card
            id="sso-sp-card"
            title="Service provider details"
            icon="hero-clipboard-document-list"
            class="lg:col-span-2"
          >
            <:description>Enter these in your identity provider's SAML app.</:description>

            <%= if @config do %>
              <div
                :if={@config.base_url && @config.base_url != @base_url}
                id="sso-host-mismatch"
                role="alert"
                class="flex gap-3 rounded-lg border border-warning/30 bg-warning/10 p-3 text-sm"
              >
                <.icon name="hero-exclamation-triangle" class="size-5 shrink-0 text-warning" />
                <span>
                  SSO was set up at <span class="font-mono">{@config.base_url}</span>, but this
                  deployment now answers at <span class="font-mono">{@base_url}</span>.
                  Update the ACS URL in your identity provider. The entity ID stays the same.
                </span>
              </div>
              <dl class="space-y-3 text-sm">
                <.copy_field
                  id="sso-entity-id"
                  label="Entity ID (Audience)"
                  value={@config.sp_entity_id}
                />
                <.copy_field
                  id="sso-acs-url"
                  label="ACS URL (Single sign-on URL)"
                  value={"#{@base_url}/sso/#{@config.id}/acs"}
                />
                <.copy_field
                  id="sso-metadata-url"
                  label="SP metadata"
                  value={"#{@base_url}/sso/#{@config.id}/metadata"}
                />
              </dl>
              <div
                :if={@config.idp_entity_id}
                class="border-t border-base-content/10 pt-3 text-xs text-base-content/60"
              >
                Trusting <span class="font-mono">{@config.idp_entity_id}</span>
                with {length(@config.idp_cert_fingerprints)} signing {if length(
                                                                           @config.idp_cert_fingerprints
                                                                         ) == 1,
                                                                         do: "certificate",
                                                                         else: "certificates"}.
              </div>
            <% else %>
              <p class="text-sm text-base-content/60">
                Save the identity provider first. The entity ID is fixed when SSO is
                set up, so a later change of host doesn't break your IdP integration.
              </p>
            <% end %>
          </.settings_card>
        </div>

        <.settings_card :if={@config} id="sso-domains-card" title="Domains" icon="hero-at-symbol">
          <:description>
            Only addresses at verified domains can sign in with this IdP. Verify a
            domain by publishing a DNS TXT record, which proves your organization
            controls it.
          </:description>

          <ul id="sso-domains" class="divide-y divide-base-content/10">
            <li :if={@config.domains == []} class="py-3 text-sm text-base-content/60">
              No domains yet.
            </li>
            <li
              :for={d <- @config.domains}
              id={"sso-domain-#{d.id}"}
              class="flex flex-col gap-3 py-3 sm:flex-row sm:items-start sm:justify-between"
            >
              <div class="min-w-0 space-y-1">
                <p class="flex items-center gap-2 font-medium">
                  {d.domain}
                  <.pill :if={Domain.verified?(d)} tone={:success}>
                    <.icon name="hero-check-badge" class="size-3.5" /> Verified
                  </.pill>
                  <.pill :if={!Domain.verified?(d)} tone={:warning}>Pending</.pill>
                </p>
                <div :if={!Domain.verified?(d)} class="space-y-1 text-xs text-base-content/70">
                  <p>Add this TXT record at your DNS provider, then verify:</p>
                  <dl class="grid grid-cols-[auto_1fr] gap-x-2 rounded-lg bg-base-300 px-3 py-2 font-mono">
                    <dt class="text-base-content/50">Name</dt>
                    <dd class="break-all select-all">{d.txt_record_name}</dd>
                    <dt class="text-base-content/50">Value</dt>
                    <dd class="break-all select-all">{d.txt_record_value}</dd>
                  </dl>
                </div>
              </div>
              <div class="flex shrink-0 gap-2">
                <.button
                  :if={!Domain.verified?(d)}
                  variant="primary"
                  phx-click="verify_sso_domain"
                  phx-value-id={d.id}
                  phx-disable-with="Checking DNS…"
                >
                  Verify
                </.button>
                <button
                  type="button"
                  phx-click="remove_sso_domain"
                  phx-value-id={d.id}
                  class={quiet_button()}
                  aria-label={"Remove #{d.domain}"}
                >
                  Remove
                </button>
              </div>
            </li>
          </ul>

          <.form
            for={@domain_form}
            id="sso-domain-form"
            phx-submit="add_sso_domain"
            class="flex flex-col gap-x-2 sm:flex-row sm:items-end"
          >
            <div class="sm:min-w-64">
              <.input
                field={@domain_form[:domain]}
                type="text"
                label="Add domain"
                placeholder="example.com"
              />
            </div>
            <div class="mb-2">
              <.button>Add domain</.button>
            </div>
          </.form>
        </.settings_card>

        <.settings_card
          :if={@config}
          id="sso-readiness-card"
          title="Readiness & enforcement"
          icon="hero-shield-check"
        >
          <:description>
            Members link their account the first time they sign in with SSO. Turn on
            enforcement once they have; members who haven't linked can still use
            SSO afterwards. Owners always keep password sign-in, as a break-glass.
          </:description>
          <:actions>
            <%= if @config.enforce_sso do %>
              <.button
                id="sso-enforce-off"
                phx-click="set_sso_enforcement"
                phx-value-enforce="false"
              >
                Stop requiring SSO
              </.button>
            <% else %>
              <.button
                id="sso-enforce-on"
                variant="primary"
                phx-click="confirm_sso_enforcement"
                disabled={!Config.verified_domain?(@config)}
                title={!Config.verified_domain?(@config) && "Verify a domain first"}
              >
                Require SSO
              </.button>
            <% end %>
          </:actions>

          <div class="space-y-2">
            <div class="flex items-baseline justify-between text-sm">
              <span>
                <span class="font-semibold" id="sso-linked-count">{@readiness.linked}</span>
                of {@readiness.total} members have signed in with SSO
              </span>
              <span class="text-base-content/60">{percent(@readiness)}%</span>
            </div>
            <div
              class="h-2 w-full overflow-hidden rounded-full bg-base-content/10"
              role="progressbar"
              aria-label="Members who have signed in with SSO"
              aria-valuemin="0"
              aria-valuemax={@readiness.total}
              aria-valuenow={@readiness.linked}
            >
              <div
                class="h-full rounded-full bg-primary transition-[width] duration-500 ease-out"
                style={"width: #{percent(@readiness)}%"}
              >
              </div>
            </div>
          </div>

          <div class="overflow-x-auto">
            <table class="w-full text-left text-sm">
              <thead class="text-xs uppercase tracking-wide text-base-content/50">
                <tr class="border-b border-base-content/10">
                  <th class="px-3 py-2 font-medium">Member</th>
                  <th class="px-3 py-2 font-medium">Role</th>
                  <th class="px-3 py-2 font-medium">SSO</th>
                </tr>
              </thead>
              <tbody id="sso-readiness" phx-update="stream" class="divide-y divide-base-content/5">
                <tr id="sso-readiness-empty" class="hidden only:table-row">
                  <td colspan="3" class="px-3 py-3 text-base-content/60">No members yet.</td>
                </tr>
                <tr
                  :for={{dom_id, row} <- @streams.sso_readiness}
                  id={dom_id}
                  class="transition-colors hover:bg-base-content/5"
                >
                  <td class="px-3 py-2 font-medium">{row.email}</td>
                  <td class="px-3 py-2 capitalize">{row.role}</td>
                  <td class="px-3 py-2">
                    <%= cond do %>
                      <% row.owner? -> %>
                        <.pill tone={:neutral}>Owner · password kept</.pill>
                      <% row.linked? -> %>
                        <.pill
                          tone={:success}
                          title={
                            row.last_sso_at &&
                              "Last SSO sign-in #{Calendar.strftime(row.last_sso_at, "%Y-%m-%d %H:%M UTC")}"
                          }
                        >
                          Linked
                        </.pill>
                      <% true -> %>
                        <.pill tone={:neutral}>Not yet</.pill>
                    <% end %>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </.settings_card>

        <.enforce_modal :if={@confirm == :enforce} readiness={@readiness} />
        <.delete_modal :if={@confirm == :delete} enforced={@config && @config.enforce_sso} />
      </div>
    <% else %>
      <.settings_card id="sso-upgrade-card" title="Single sign-on" icon="hero-building-office-2">
        <:description>
          Let members sign in with your identity provider over SAML 2.0, create
          accounts on first sign-in, and require SSO for your organization.
        </:description>
        <UpgradePrompt.upgrade_prompt feature={:sso} />
      </.settings_card>
    <% end %>
    """
  end

  attr :config, :any, required: true
  attr :readiness, :map, required: true

  defp status_strip(assigns) do
    assigns =
      assign(assigns, :steps, [
        {"Identity provider", !!assigns.config},
        {"Verified domain", !!assigns.config && Config.verified_domain?(assigns.config)},
        {"Members linked", !!assigns.config && assigns.readiness.linked > 0},
        {"SSO required", !!assigns.config && assigns.config.enforce_sso}
      ])

    ~H"""
    <ol id="sso-status" class="grid grid-cols-2 gap-2 sm:grid-cols-4" aria-label="SSO setup progress">
      <li
        :for={{{label, done}, index} <- Enum.with_index(@steps, 1)}
        aria-current={!done && "step"}
        class={[
          "flex items-center gap-2 rounded-lg border px-3 py-2 text-xs font-medium transition-colors",
          if(done,
            do: "border-primary/30 bg-primary/5 text-base-content",
            else: "border-base-content/10 text-base-content/50"
          )
        ]}
      >
        <span class={[
          "flex size-5 shrink-0 items-center justify-center rounded-full text-[10px] font-semibold",
          if(done, do: "bg-primary text-primary-content", else: "bg-base-content/10")
        ]}>
          <.icon :if={done} name="hero-check" class="size-3" />
          <span :if={!done}>{index}</span>
        </span>
        {label}
      </li>
    </ol>
    """
  end

  attr :tone, :atom, values: [:success, :warning, :neutral], required: true
  attr :rest, :global
  slot :inner_block, required: true

  defp pill(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset",
        pill_tone(@tone)
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp pill_tone(:success), do: "bg-success/10 text-success ring-success/30"
  defp pill_tone(:warning), do: "bg-warning/10 text-warning ring-warning/30"
  defp pill_tone(:neutral), do: "bg-base-content/5 text-base-content/70 ring-base-content/15"

  attr :id, :string, required: true
  attr :title_id, :string, required: true
  slot :inner_block, required: true
  slot :actions, required: true

  # A confirmation dialog. Escape and a click on the backdrop both cancel.
  defp confirm_dialog(assigns) do
    ~H"""
    <div
      id={@id}
      role="dialog"
      aria-modal="true"
      aria-labelledby={@title_id}
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown="cancel_sso_confirm"
      phx-key="escape"
    >
      <div
        class="absolute inset-0 bg-black/40 backdrop-blur-sm"
        phx-click="cancel_sso_confirm"
        aria-hidden="true"
      >
      </div>
      <div class="relative w-full max-w-md space-y-3 rounded-2xl border border-base-content/10 bg-base-100 p-6 shadow-xl">
        {render_slot(@inner_block)}
        <div class="flex justify-end gap-2 pt-2">
          <button type="button" phx-click="cancel_sso_confirm" class={quiet_button()}>Cancel</button>
          {render_slot(@actions)}
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true

  defp copy_field(assigns) do
    ~H"""
    <div>
      <dt class="mb-1 text-xs font-medium text-base-content/60">{@label}</dt>
      <dd
        id={@id}
        class="select-all break-all rounded-lg bg-base-300 px-3 py-2 font-mono text-xs transition-colors hover:bg-base-100"
      >
        {@value}
      </dd>
    </div>
    """
  end

  attr :readiness, :map, required: true

  defp enforce_modal(assigns) do
    assigns = assign(assigns, :unlinked, assigns.readiness.total - assigns.readiness.linked)

    ~H"""
    <.confirm_dialog id="sso-enforce-modal" title_id="sso-enforce-title">
      <h3 id="sso-enforce-title" class="text-lg font-semibold">Require single sign-on?</h3>
      <ul class="list-disc space-y-1 pl-5 text-sm text-base-content/80">
        <li>
          Members other than owners will no longer be able to sign in with a
          password or email link.
        </li>
        <li>
          <span class="font-semibold">Everyone except owners is signed out now</span>
          and must sign in again with SSO.
        </li>
        <li :if={@unlinked > 0}>
          <span class="font-semibold">
            {@unlinked} {if @unlinked == 1, do: "member hasn't", else: "members haven't"}
          </span>
          signed in with SSO yet. They can still do so, provided your identity
          provider has them.
        </li>
        <li>Passwords are kept, so turning this off restores access. API keys are unaffected.</li>
      </ul>
      <:actions>
        <.button
          id="sso-enforce-confirm"
          variant="primary"
          phx-click="set_sso_enforcement"
          phx-value-enforce="true"
          phx-disable-with="Applying…"
        >
          Require SSO and sign members out
        </.button>
      </:actions>
    </.confirm_dialog>
    """
  end

  attr :enforced, :boolean, default: false

  defp delete_modal(assigns) do
    ~H"""
    <.confirm_dialog id="sso-delete-modal" title_id="sso-delete-title">
      <h3 id="sso-delete-title" class="text-lg font-semibold">Remove single sign-on?</h3>
      <p class="text-sm text-base-content/80">
        This deletes the identity provider, its domains and every member's SSO
        link. <span :if={@enforced}>Enforcement ends and members can use passwords again.</span>
        Members created through SSO have no password; they can sign in with an
        email link.
      </p>
      <:actions>
        <button
          type="button"
          id="sso-delete-confirm"
          phx-click="delete_sso_config"
          class={danger_button()}
        >
          Remove SSO
        </button>
      </:actions>
    </.confirm_dialog>
    """
  end

  defp percent(%{total: 0}), do: 0
  defp percent(%{total: total, linked: linked}), do: round(linked * 100 / total)

  defp code_textarea, do: @code_textarea
  defp quiet_button, do: @quiet_button
  defp danger_quiet_button, do: @danger_quiet_button
  defp danger_button, do: @danger_button

  defp role_options, do: [{"Admin", "admin"}, {"Member", "member"}, {"Viewer", "viewer"}]

  defp team_options(teams), do: [{"Select team", ""} | Enum.map(teams, &{&1.name, &1.id})]
end
