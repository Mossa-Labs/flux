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
                class="btn btn-ghost btn-xs text-error hover:bg-error/10"
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
                class="textarea w-full font-mono text-xs"
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
                  class="textarea w-full font-mono text-xs"
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

              <.button class="btn btn-primary btn-sm" phx-disable-with="Saving…">
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
                class="alert alert-warning text-sm"
              >
                <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
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
                  <span :if={Domain.verified?(d)} class="badge badge-success badge-sm gap-1">
                    <.icon name="hero-check-badge" class="size-3.5" /> Verified
                  </span>
                  <span :if={!Domain.verified?(d)} class="badge badge-warning badge-sm">Pending</span>
                </p>
                <div :if={!Domain.verified?(d)} class="space-y-1 text-xs text-base-content/70">
                  <p>Add this TXT record at your DNS provider, then verify:</p>
                  <dl class="grid grid-cols-[auto_1fr] gap-x-2 rounded-box bg-base-300 px-3 py-2 font-mono">
                    <dt class="text-base-content/50">Name</dt>
                    <dd class="break-all select-all">{d.txt_record_name}</dd>
                    <dt class="text-base-content/50">Value</dt>
                    <dd class="break-all select-all">{d.txt_record_value}</dd>
                  </dl>
                </div>
              </div>
              <div class="flex shrink-0 gap-2">
                <button
                  :if={!Domain.verified?(d)}
                  type="button"
                  phx-click="verify_sso_domain"
                  phx-value-id={d.id}
                  phx-disable-with="Checking DNS…"
                  class="btn btn-primary btn-xs"
                >
                  Verify
                </button>
                <button
                  type="button"
                  phx-click="remove_sso_domain"
                  phx-value-id={d.id}
                  class="btn btn-ghost btn-xs"
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
              <.button class="btn btn-sm">Add domain</.button>
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
              <button
                type="button"
                id="sso-enforce-off"
                phx-click="set_sso_enforcement"
                phx-value-enforce="false"
                class="btn btn-sm"
              >
                Stop requiring SSO
              </button>
            <% else %>
              <button
                type="button"
                id="sso-enforce-on"
                phx-click="confirm_sso_enforcement"
                disabled={!Config.verified_domain?(@config)}
                title={!Config.verified_domain?(@config) && "Verify a domain first"}
                class="btn btn-primary btn-sm"
              >
                Require SSO
              </button>
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
            <progress
              class="progress progress-primary w-full"
              value={@readiness.linked}
              max={max(@readiness.total, 1)}
            ></progress>
          </div>

          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Member</th>
                  <th>Role</th>
                  <th>SSO</th>
                </tr>
              </thead>
              <tbody id="sso-readiness" phx-update="stream">
                <tr id="sso-readiness-empty" class="hidden only:table-row">
                  <td colspan="3" class="text-base-content/60">No members yet.</td>
                </tr>
                <tr :for={{dom_id, row} <- @streams.sso_readiness} id={dom_id}>
                  <td class="font-medium">{row.email}</td>
                  <td class="capitalize">{row.role}</td>
                  <td>
                    <%= cond do %>
                      <% row.owner? -> %>
                        <span class="badge badge-ghost badge-sm">Owner · password kept</span>
                      <% row.linked? -> %>
                        <span
                          class="badge badge-success badge-sm"
                          title={
                            row.last_sso_at &&
                              "Last SSO sign-in #{Calendar.strftime(row.last_sso_at, "%Y-%m-%d %H:%M UTC")}"
                          }
                        >
                          Linked
                        </span>
                      <% true -> %>
                        <span class="badge badge-ghost badge-sm text-base-content/60">Not yet</span>
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
    ~H"""
    <ol id="sso-status" class="steps steps-horizontal w-full text-xs">
      <li class={["step", @config && "step-primary"]}>Identity provider</li>
      <li class={["step", @config && Config.verified_domain?(@config) && "step-primary"]}>
        Verified domain
      </li>
      <li class={["step", @config && @readiness.linked > 0 && "step-primary"]}>Members linked</li>
      <li class={["step", @config && @config.enforce_sso && "step-primary"]}>SSO required</li>
    </ol>
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
        class="select-all break-all rounded-box bg-base-300 px-3 py-2 font-mono text-xs transition-colors hover:bg-base-100"
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
    <div
      class="modal modal-open"
      id="sso-enforce-modal"
      role="dialog"
      aria-labelledby="sso-enforce-title"
    >
      <div class="modal-box space-y-3">
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
            <span class="font-semibold">{@unlinked} {if @unlinked == 1,
              do: "member hasn't",
              else: "members haven't"}</span>
            signed in with SSO yet. They can still do so, provided your identity
            provider has them.
          </li>
          <li>Passwords are kept, so turning this off restores access. API keys are unaffected.</li>
        </ul>
        <div class="modal-action">
          <button type="button" phx-click="cancel_sso_confirm" class="btn btn-ghost">Cancel</button>
          <button
            type="button"
            id="sso-enforce-confirm"
            phx-click="set_sso_enforcement"
            phx-value-enforce="true"
            phx-disable-with="Applying…"
            class="btn btn-primary"
          >
            Require SSO and sign members out
          </button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="cancel_sso_confirm"></div>
    </div>
    """
  end

  attr :enforced, :boolean, default: false

  defp delete_modal(assigns) do
    ~H"""
    <div
      class="modal modal-open"
      id="sso-delete-modal"
      role="dialog"
      aria-labelledby="sso-delete-title"
    >
      <div class="modal-box space-y-3">
        <h3 id="sso-delete-title" class="text-lg font-semibold">Remove single sign-on?</h3>
        <p class="text-sm text-base-content/80">
          This deletes the identity provider, its domains and every member's SSO
          link. <span :if={@enforced}>Enforcement ends and members can use passwords again.</span>
          Members created through SSO have no password; they can sign in with an
          email link.
        </p>
        <div class="modal-action">
          <button type="button" phx-click="cancel_sso_confirm" class="btn btn-ghost">Cancel</button>
          <button
            type="button"
            id="sso-delete-confirm"
            phx-click="delete_sso_config"
            class="btn btn-error"
          >
            Remove SSO
          </button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="cancel_sso_confirm"></div>
    </div>
    """
  end

  defp percent(%{total: 0}), do: 0
  defp percent(%{total: total, linked: linked}), do: round(linked * 100 / total)

  defp role_options, do: [{"Admin", "admin"}, {"Member", "member"}, {"Viewer", "viewer"}]

  defp team_options(teams), do: [{"Select team", ""} | Enum.map(teams, &{&1.name, &1.id})]
end
