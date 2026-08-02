defmodule FluxWeb.SystemSettingsLive do
  @moduledoc """
  Owner-only system settings: manage teams and users.
  Renders 403 with 20-second redirect when not authorized.
  """
  use FluxWeb, :live_view

  alias Flux.Accounts
  alias Flux.Permissions
  alias Flux.Repo
  alias Flux.Security
  alias Flux.Structure
  alias Flux.Structure.{OrganizationMember, Team, TeamMember}
  alias FluxWeb.Components.Brand
  alias FluxWeb.Components.UpgradePrompt

  @redirect_after_ms 20_000
  @tick_ms 1_000

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    authorized = scope && Permissions.can?(scope, :view_system_settings)

    if authorized do
      org_id = scope.organization_id
      rbac_mode = Flux.RBAC.mode()
      teams = if org_id, do: Structure.list_teams(scope), else: []
      members = load_members(scope, org_id, rbac_mode)

      {:ok,
       socket
       |> assign(:active_tab, :system_settings)
       |> assign(:page_title, "System Settings")
       |> assign(:authorized, true)
       |> assign(:org_id, org_id)
       |> assign(:rbac_mode, rbac_mode)
       |> assign(:license, load_license())
       |> assign(:node_states, Flux.License.node_states())
       |> assign(:node_capacity, Flux.License.node_capacity())
       |> assign(:activation_supported, Flux.License.activation_supported?())
       |> assign(:license_form, to_form(%{"token" => ""}, as: :license))
       |> assign(:teams, teams)
       |> assign(:members, members)
       |> assign(:team_form, nil)
       |> assign(:member_form, nil)
       |> assign(:editing_member_id, nil)
       |> assign(:api_keys, if(org_id, do: Accounts.list_api_keys(org_id), else: []))
       |> assign(:api_key_form, new_api_key_form())
       |> assign(:revealed_key, nil)
       |> assign(:api_key_scopes_enabled, Flux.License.has_feature?(:api_key_scopes))
       |> assign(:password_policy_enabled, Flux.License.has_feature?(:password_policy))
       |> assign(:mfa_enforcement_enabled, Flux.License.has_feature?(:mfa_enforcement))
       |> assign(:branding_enabled, Flux.Branding.entitled?())
       |> assign_branding(org_id)
       |> assign(:usage_metering_enabled, usage_metering_enabled?())
       |> assign(:usage, load_usage(org_id))
       |> assign_security_settings(org_id)
       |> stream(:teams_stream, teams)}
    else
      Process.send_after(self(), :redirect_to_dashboard, @redirect_after_ms)
      Process.send_after(self(), :tick, @tick_ms)

      {:ok,
       socket
       |> assign(:active_tab, :system_settings)
       |> assign(:page_title, "Forbidden")
       |> assign(:authorized, false)
       |> assign(:seconds_left, 20)}
    end
  end

  @impl true
  def handle_info(:redirect_to_dashboard, socket) do
    {:noreply, redirect(socket, to: ~p"/dashboard")}
  end

  def handle_info(:tick, socket) do
    if socket.assigns.authorized do
      {:noreply, socket}
    else
      secs = socket.assigns.seconds_left

      if secs <= 1 do
        {:noreply, redirect(socket, to: ~p"/dashboard")}
      else
        Process.send_after(self(), :tick, @tick_ms)
        {:noreply, assign(socket, :seconds_left, secs - 1)}
      end
    end
  end

  defp load_license do
    case Flux.License.fetch() do
      {:ok, license} -> Map.put(license, :tier, Flux.License.tier())
      {:error, _} -> %{tier: Flux.License.tier(), org: nil, valid_until: nil, node_count: nil}
    end
  end

  defp activate_license(""), do: {:error, :empty}
  defp activate_license(token), do: Flux.License.apply_license(token)

  # Feature gating flips immediately, but services are wired up at boot, so a tier
  # change is not fully in effect until every node restarts.
  #
  # Do NOT branch on how many nodes are visible. That count is what this node can
  # currently SEE, and on a first activation it can see nothing: cluster formation
  # is itself a licensed capability, so nodes that have never been licensed have
  # not connected and each reports a cluster of one. Branching on it produced
  # exactly the wrong advice — "restart the node", singular — on precisely the
  # deployments where every node needs restarting.
  #
  # "Every node" is true at every size, so it needs no condition.
  defp activation_message(license) do
    tier = license |> Map.get(:tier, Flux.License.tier()) |> to_string() |> String.capitalize()

    "#{tier} license applied — restart every Flux node to finish enabling its features. " <>
      "On a multi-node deployment that means all of them, including this one."
  end

  defp license_error(:empty), do: "the token is empty"
  defp license_error(:unsupported), do: "activation isn't available in this build"
  defp license_error(:invalid_signature), do: "the signature is invalid"
  defp license_error(:not_writable), do: "the license file location is not writable"
  defp license_error(reason), do: inspect(reason)

  defp usage_metering_enabled?, do: Flux.License.has_feature?(:usage_metering)

  # Only fetch real usage when metering is entitled; the Community build shows
  # an upgrade prompt instead (metering is a Pro feature).
  defp load_usage(nil), do: nil

  defp load_usage(org_id) do
    if usage_metering_enabled?() do
      case Flux.Metering.get_usage(org_id) do
        {:ok, usage} -> usage
        {:error, _} -> nil
      end
    else
      nil
    end
  end

  defp assign_security_settings(socket, nil) do
    socket
    |> assign(:security_settings, nil)
    |> assign(:security_form, security_form(%Security.SecuritySettings{}))
    |> assign(:security_error, nil)
  end

  defp assign_security_settings(socket, org_id) do
    settings = Security.get_settings(org_id)

    socket
    |> assign(:security_settings, settings)
    |> assign(:security_form, security_form(settings))
    |> assign(:security_error, nil)
  end

  attr :enabled, :boolean, required: true
  attr :branding, :map, required: true
  attr :form, :any, required: true

  defp branding_section(assigns) do
    ~H"""
    <section class="card bg-base-100 shadow-sm border border-base-200">
      <div class="card-body">
        <h2 class="card-title text-base font-bold">
          <.icon name="hero-paint-brush" class="w-5 h-5" /> Branding
        </h2>
        <p class="text-sm text-base-content/60">
          Replace the Flux name and accent colour with your own.
        </p>

        <%= if @enabled do %>
          <.form for={@form} id="branding-form" phx-submit="save_branding" class="mt-2 space-y-3">
            <.input field={@form[:brand_name]} type="text" label="Brand name" maxlength="40" />
            <.input
              field={@form[:primary_color]}
              type="color"
              label="Accent colour"
            />
            <.input
              field={@form[:login_message]}
              type="textarea"
              label="Sign-in message"
              placeholder="Shown to everyone on the sign-in page"
            />

            <%!--
            A preview rather than a live preview. The chrome only re-reads
            branding on a full page load, so showing the saved result here is
            honest; animating it as you type would imply the header updates too.
            --%>
            <div class="rounded-lg border border-base-200 p-3">
              <p class="text-xs text-base-content/60 mb-2">Currently applied</p>
              <Brand.brand_mark branding={@branding} />
            </div>

            <p class="text-xs text-base-content/60">
              The accent colour and icon apply on the next full page load.
            </p>

            <.button phx-disable-with="Saving…" class="btn-primary">Save branding</.button>
          </.form>
        <% else %>
          <UpgradePrompt.upgrade_prompt feature={:white_label} size={:compact} />
        <% end %>
      </div>
    </section>
    """
  end

  defp assign_branding(socket, org_id) do
    theme = Flux.Branding.for_org(org_id)

    socket
    |> assign(:branding, theme)
    |> assign(:branding_form, branding_form(theme))
  end

  # Built from plain params rather than a changeset: the branding schema lives
  # behind the provider contract, so there is no struct here to cast against.
  # Errors come back from the provider as a keyword list and are attached below.
  defp branding_form(%Flux.Branding.Theme{} = theme, errors \\ []) do
    to_form(
      %{
        "brand_name" => theme.brand_name,
        "primary_color" => theme.primary_color || Flux.Branding.Theme.stock_primary(),
        "login_message" => theme.login_message || ""
      },
      as: :branding,
      errors: errors
    )
  end

  # Shared form for the security section: the allowlist renders one CIDR per
  # line, the current session-timeout selection, and the password policy.
  defp security_form(%Security.SecuritySettings{} = settings) do
    to_form(
      %{
        "ip_allowlist" => Enum.join(settings.ip_allowlist || [], "\n"),
        "session_timeout_minutes" => to_string(settings.session_timeout_minutes || 43_200),
        "password_min_length" => to_string(settings.password_min_length || 12),
        "password_require_upper" => settings.password_require_upper || false,
        "password_require_lower" => settings.password_require_lower || false,
        "password_require_number" => settings.password_require_number || false,
        "password_require_special" => settings.password_require_special || false,
        "password_rotation_days" => to_string(settings.password_rotation_days || ""),
        "require_mfa" => settings.require_mfa || false
      },
      as: :security
    )
  end

  defp security_error(changeset) do
    case Keyword.get(changeset.errors, :ip_allowlist) do
      {msg, _opts} -> msg
      _ -> "Could not save the IP allowlist."
    end
  end

  # Surface the first password-policy field error (min length / rotation) with
  # the offending field name, falling back to a generic message.
  defp password_policy_error(changeset) do
    case changeset.errors do
      [{field, {msg, _opts}} | _] ->
        "#{field |> to_string() |> String.replace("_", " ") |> String.capitalize()} #{msg}."

      _ ->
        "Could not save the password policy."
    end
  end

  defp load_members(_scope, nil, _), do: []

  defp load_members(scope, _org_id, :org_centric),
    do: Structure.list_organization_members(scope.organization_id)

  defp load_members(scope, _org_id, :team_centric), do: Structure.list_team_members(scope)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%= if @authorized do %>
        <.authorized_content
          org_id={@org_id}
          current_scope={@current_scope}
          license={@license}
          activation_supported={@activation_supported}
          license_form={@license_form}
          node_states={@node_states}
          node_capacity={@node_capacity}
          branding_enabled={@branding_enabled}
          branding={@branding}
          branding_form={@branding_form}
          teams={@teams}
          members={@members}
          rbac_mode={@rbac_mode}
          team_form={@team_form}
          member_form={@member_form}
          editing_member_id={@editing_member_id}
          api_keys={@api_keys}
          api_key_form={@api_key_form}
          revealed_key={@revealed_key}
          api_key_scopes_enabled={@api_key_scopes_enabled}
          password_policy_enabled={@password_policy_enabled}
          mfa_enforcement_enabled={@mfa_enforcement_enabled}
          usage_metering_enabled={@usage_metering_enabled}
          usage={@usage}
          security_form={@security_form}
          security_error={@security_error}
          streams={@streams}
        />
      <% else %>
        <.forbidden_content seconds_left={@seconds_left} />
      <% end %>
    </div>
    """
  end

  defp forbidden_content(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-16 text-center max-w-md mx-auto">
      <div class="p-4 bg-error/10 rounded-full mb-4">
        <.icon name="hero-shield-exclamation" class="w-12 h-12 text-error" />
      </div>
      <h1 class="text-2xl font-bold text-base-content">403 Forbidden</h1>
      <p class="text-base-content/70 mt-2">
        You don't have permission to access System Settings.
      </p>
      <p class="text-base-content/60 mt-4">
        You will be redirected to the dashboard in {@seconds_left} seconds.
      </p>
      <.link navigate={~p"/dashboard"} class="btn btn-primary mt-6">
        Go to Dashboard
      </.link>
    </div>
    """
  end

  defp authorized_content(assigns) do
    ~H"""
    <div class="space-y-8">
      <div>
        <h1 class="text-2xl font-bold tracking-tight text-base-content">
          System Settings
        </h1>
        <p class="text-base-content/60 mt-1">Manage teams and users for your organization</p>
      </div>

      <.license_section
        license={@license}
        activation_supported={@activation_supported}
        license_form={@license_form}
        node_states={@node_states}
        node_capacity={@node_capacity}
      />

      <.usage_section enabled={@usage_metering_enabled} usage={@usage} />

      <.branding_section
        :if={@org_id}
        enabled={@branding_enabled}
        branding={@branding}
        form={@branding_form}
      />

      <%= if @org_id do %>
        <.teams_section
          scope={@current_scope}
          teams={@teams}
          team_form={@team_form}
          stream_name={:teams_stream}
          streams={@streams}
        />
        <.members_section
          scope={@current_scope}
          members={@members}
          teams={@teams}
          rbac_mode={@rbac_mode}
          member_form={@member_form}
          editing_member_id={@editing_member_id}
        />
        <.api_keys_section
          api_keys={@api_keys}
          api_key_form={@api_key_form}
          revealed_key={@revealed_key}
          scopes_enabled={@api_key_scopes_enabled}
        />
        <.security_section
          form={@security_form}
          error={@security_error}
          password_policy_enabled={@password_policy_enabled}
          mfa_enforcement_enabled={@mfa_enforcement_enabled}
        />
      <% else %>
        <p class="text-base-content/60">
          No organization in scope. Create or select an organization first.
        </p>
      <% end %>

      <.about_section />
    </div>
    """
  end

  # Full build identity, behind auth. The footer carries version + revision for
  # everyone; the toolchain and exact build time sit here because an
  # unauthenticated, precisely-versioned instance is easier to match against
  # published CVEs.
  defp about_section(assigns) do
    assigns = assign(assigns, :build, Flux.BuildInfo.to_map())

    ~H"""
    <section class="card bg-base-100 shadow-sm border border-base-200">
      <div class="card-body">
        <div class="flex items-start justify-between gap-4">
          <div>
            <h2 class="card-title text-base-content">About this build</h2>
            <p class="text-sm text-base-content/60 mt-1">
              Quote this when contacting support.
            </p>
          </div>
          <button
            type="button"
            class="btn btn-sm btn-ghost gap-2"
            id="copy-build-info"
            phx-hook=".CopyBuildInfo"
            data-build={Flux.BuildInfo.long()}
          >
            <.icon name="hero-clipboard-document" class="w-4 h-4" /> Copy
          </button>
        </div>

        <dl class="mt-4 grid grid-cols-1 gap-x-6 gap-y-2 sm:grid-cols-2 text-sm">
          <div class="flex justify-between sm:block">
            <dt class="text-base-content/60">Edition</dt>
            <dd class="font-medium text-base-content">{@build.edition}</dd>
          </div>
          <div class="flex justify-between sm:block">
            <dt class="text-base-content/60">Version</dt>
            <dd class="font-medium text-base-content">{@build.version}</dd>
          </div>
          <div class="flex justify-between sm:block">
            <dt class="text-base-content/60">Core revision</dt>
            <dd class="font-mono text-xs text-base-content">{@build.core_sha}</dd>
          </div>
          <div :if={@build.edition_sha} class="flex justify-between sm:block">
            <dt class="text-base-content/60">Edition revision</dt>
            <dd class="font-mono text-xs text-base-content">{@build.edition_sha}</dd>
          </div>
          <div class="flex justify-between sm:block">
            <dt class="text-base-content/60">Toolchain</dt>
            <dd class="font-medium text-base-content">
              OTP {@build.otp} / Elixir {@build.elixir}
            </dd>
          </div>
          <div class="flex justify-between sm:block">
            <dt class="text-base-content/60">Built</dt>
            <dd class="font-medium text-base-content">{@build.built_at || "—"}</dd>
          </div>
        </dl>

        <p :if={not @build.released} class="mt-4 text-xs text-warning">
          <.icon name="hero-exclamation-triangle" class="w-4 h-4 inline-block align-text-bottom" />
          This build carries no source revision, so it was not produced by the release
          pipeline and cannot be reproduced from a tag.
        </p>
      </div>
    </section>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyBuildInfo">
      export default {
        mounted() {
          this.el.addEventListener("click", () => {
            navigator.clipboard.writeText(this.el.dataset.build).then(() => {
              const original = this.el.innerHTML
              this.el.textContent = "Copied"
              setTimeout(() => { this.el.innerHTML = original }, 1500)
            })
          })
        }
      }
    </script>
    """
  end

  attr :form, :any, required: true
  attr :error, :string, default: nil
  attr :password_policy_enabled, :boolean, default: false
  attr :mfa_enforcement_enabled, :boolean, default: false

  defp security_section(assigns) do
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

  attr :license, :map, required: true
  attr :activation_supported, :boolean, default: false
  attr :license_form, :any, default: nil
  attr :node_states, :list, default: []
  attr :node_capacity, :any, default: nil

  defp license_section(assigns) do
    ~H"""
    <section class="card bg-base-100 shadow-sm border border-base-200">
      <div class="card-body">
        <div class="flex items-center justify-between">
          <h2 class="card-title text-base font-bold">
            <.icon name="hero-key" class="w-5 h-5" /> License
          </h2>
          <span class={[
            "badge badge-lg font-semibold capitalize",
            tier_badge_class(@license.tier)
          ]}>
            {@license.tier}
          </span>
        </div>

        <dl class="mt-4 grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div>
            <dt class="text-sm text-base-content/60">Organization</dt>
            <dd class="font-medium">{license_value(Map.get(@license, :org))}</dd>
          </div>
          <div>
            <dt class="text-sm text-base-content/60">Expires</dt>
            <dd class="font-medium">{format_expiry(Map.get(@license, :valid_until))}</dd>
          </div>
          <div>
            <dt class="text-sm text-base-content/60">Licensed nodes</dt>
            <dd class="font-medium">{license_value(Map.get(@license, :node_count))}</dd>
          </div>
        </dl>

        <.license_status_banner license={@license} />

        <p :if={@license.tier == :community} class="text-sm text-base-content/60 mt-2">
          Running the Community tier.
          <.link href="https://fluxdata.tech/pricing" class="link link-primary">Upgrade</.link>
          to unlock Pro and Enterprise features.
        </p>

        <.cluster_license_state
          node_states={@node_states}
          node_count={Map.get(@license, :node_count)}
          node_capacity={@node_capacity}
        />

        <.activate_license_form :if={@activation_supported} form={@license_form} />
      </div>
    </section>
    """
  end

  # Shown when there is more than one node to compare, OR when the license covers
  # more nodes than are currently reachable.
  #
  # That second case is the one that used to be invisible. Cluster formation is a
  # licensed capability, so a freshly-licensed multi-node deployment reports
  # exactly one node until each has restarted — and a table that hid itself at one
  # row turned "your other nodes have not picked this up yet" into silence.
  #
  # A single-node install with a single-node license still shows nothing: the badge
  # above already says everything, and a one-row table would be noise.
  defp show_cluster_state?(node_states, node_count, node_capacity) do
    length(node_states) > 1 or
      (is_integer(node_count) and node_count > length(node_states)) or
      over_capacity?(node_capacity)
  end

  # Whether the deployment is over its licensed node count is the PROVIDER's
  # verdict, not a comparison made here. Editions that do not cap nodes report
  # nil, and so does an uncapped license, so both render as "nothing to say".
  #
  # Deliberately not `capacity.live > capacity.licensed`: what counts as a node
  # is a licensing question, and a second comparison in the UI is a second
  # definition — one that would eventually disagree with the one that writes the
  # log line. Render the verdict; do not re-derive it.
  defp over_capacity?(%{over?: true}), do: true
  defp over_capacity?(_), do: false

  # `node_count` is nil for an unlimited license — the is_integer/1 guard keeps
  # that out of the comparison rather than treating it as zero.
  defp node_shortfall(node_states, node_count) do
    if is_integer(node_count) and node_count > length(node_states) do
      {node_count, length(node_states)}
    end
  end

  attr :node_states, :list, default: []
  attr :node_count, :any, default: nil
  attr :node_capacity, :any, default: nil

  defp cluster_license_state(assigns) do
    ~H"""
    <div
      :if={show_cluster_state?(@node_states, @node_count, @node_capacity)}
      id="cluster-license-state"
      class="mt-4"
    >
      <div class="flex items-center justify-between">
        <h3 class="text-sm font-semibold text-base-content/80">
          Nodes
          <span :if={@node_capacity} class="ml-1 font-normal text-base-content/60">
            {@node_capacity.live} of {@node_capacity.licensed}
          </span>
        </h3>
        <span :if={divergent?(@node_states)} class="badge badge-warning badge-sm gap-1">
          <.icon name="hero-exclamation-triangle" class="w-3 h-3" /> Not yet consistent
        </span>
      </div>

      <p :if={divergent?(@node_states)} class="mt-1 text-xs text-base-content/60">
        These nodes are not all running the same license yet. Feature gating follows
        the license immediately, but services are wired up at boot — finish the
        rolling restart so every node matches.
      </p>

      <%!--
      Distinct from the divergence warning above: that one means the nodes we can
      see disagree, this one means we cannot see all the nodes we are licensed for.
      A node that has not restarted since activation has not joined the cluster, so
      it is absent rather than inconsistent.
      --%>
      <p :if={shortfall = node_shortfall(@node_states, @node_count)} class="mt-1 text-xs text-warning">
        Licensed for {elem(shortfall, 0)} nodes; {elem(shortfall, 1)} currently reachable.
        A node that has not restarted since the license was applied does not join the
        cluster and will not appear here.
      </p>

      <%!--
      The mirror of the shortfall above: that one means we cannot see every node
      we are licensed for, this one means we can see more than we are licensed
      for. Warning-toned rather than an error banner on purpose — nothing is
      broken, and Flux keeps running; this is a commercial state, not an outage.
      --%>
      <p :if={over_capacity?(@node_capacity)} class="mt-1 text-xs text-warning">
        Running {@node_capacity.live} nodes on a license for {@node_capacity.licensed}.
        Flux keeps running, but this is an unsupported configuration — reduce to {@node_capacity.licensed} nodes or <.link
          href="https://fluxdata.tech/pricing"
          class="link"
        >extend your license</.link>.
      </p>

      <ul class="mt-2 divide-y divide-base-200 rounded-md border border-base-200">
        <li :for={n <- @node_states} class="flex items-center justify-between px-3 py-2 text-sm">
          <span class="font-mono text-xs text-base-content/70">{n.node}</span>
          <span class={[
            "badge badge-sm capitalize",
            node_tier_class(Map.get(n, :tier))
          ]}>
            {Map.get(n, :tier)}
          </span>
        </li>
      </ul>
    </div>
    """
  end

  defp divergent?(node_states) do
    node_states
    |> Enum.map(&{Map.get(&1, :tier), Map.get(&1, :license_id)})
    |> Enum.uniq()
    |> length() > 1
  end

  # An unreachable node is called out rather than shown as unlicensed: during a
  # rolling restart "we could not ask" and "it has no license" are different
  # problems, and conflating them sends the operator the wrong way.
  defp node_tier_class(:unreachable), do: "badge-ghost text-base-content/50"
  defp node_tier_class(:community), do: "badge-ghost"
  defp node_tier_class(_), do: "badge-success"

  attr :license, :map, required: true

  defp license_status_banner(assigns) do
    assigns = assign(assigns, :status, Map.get(assigns.license, :status, :active))

    ~H"""
    <div
      :if={@status == :near_expiry}
      class="mt-3 rounded-md border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-900"
    >
      <.icon name="hero-clock" class="w-4 h-4 inline" />
      Your license expires on {format_expiry(Map.get(@license, :valid_until))}. Renew soon to avoid
      interruption.
    </div>
    <div
      :if={@status == :grace}
      class="mt-3 rounded-md border border-orange-300 bg-orange-50 px-3 py-2 text-sm text-orange-900"
    >
      <.icon name="hero-exclamation-triangle" class="w-4 h-4 inline" />
      Your license expired on {format_expiry(Map.get(@license, :valid_until))}. Pro stays active
      during the grace period — apply a renewed license to continue.
    </div>
    <div
      :if={@status == :expired}
      class="mt-3 rounded-md border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-900"
    >
      <.icon name="hero-x-circle" class="w-4 h-4 inline" />
      Your license expired on {format_expiry(Map.get(@license, :valid_until))}. Apply a renewed
      license to keep Pro features.
    </div>
    """
  end

  attr :form, :any, required: true

  defp activate_license_form(assigns) do
    ~H"""
    <div class="mt-4 border-t border-base-200 pt-4">
      <h3 class="text-sm font-semibold">Activate Pro</h3>
      <p class="text-xs text-base-content/60 mt-1">
        Paste your signed license token to activate Pro on this node.
      </p>
      <.form
        for={@form}
        id="activate-license-form"
        phx-submit="activate_license"
        class="mt-2 space-y-2"
      >
        <.input
          field={@form[:token]}
          type="textarea"
          rows="3"
          placeholder="flux license token…"
          class="w-full textarea font-mono text-xs break-all"
        />
        <.button class="btn btn-primary btn-sm">Activate license</.button>
      </.form>
    </div>
    """
  end

  attr :enabled, :boolean, required: true
  attr :usage, :map, default: nil

  defp usage_section(assigns) do
    ~H"""
    <section class="card bg-base-100 shadow-sm border border-base-200">
      <div class="card-body">
        <h2 class="card-title text-base font-bold">
          <.icon name="hero-chart-bar" class="w-5 h-5" /> Usage & Quotas
        </h2>

        <%= cond do %>
          <% !@enabled -> %>
            <div class="mt-2">
              <UpgradePrompt.upgrade_prompt feature={:usage_metering} />
            </div>
          <% is_nil(@usage) -> %>
            <p class="text-sm text-base-content/60 mt-2">Usage data is not available yet.</p>
          <% true -> %>
            <.usage_body usage={@usage} />
        <% end %>
      </div>
    </section>
    """
  end

  attr :usage, :map, required: true

  defp usage_body(assigns) do
    assigns =
      assigns
      |> assign(:metrics, Map.get(assigns.usage, :metrics, %{}))
      |> assign(:quota, Map.get(assigns.usage, :quota, %{}))

    ~H"""
    <div class="space-y-4">
      <div :if={!Map.get(@quota, :unlimited, true)} class="space-y-1">
        <div class="flex items-center justify-between text-sm">
          <span class="text-base-content/70">
            Messages this period
            <span :if={Map.get(@quota, :state) == :warn} class="badge badge-warning badge-sm ml-1">
              {usage_pct(@quota)}% used
            </span>
            <span :if={Map.get(@quota, :state) == :over} class="badge badge-error badge-sm ml-1">
              over quota
            </span>
          </span>
          <span class="font-medium">
            {format_metric(:messages_ingested, Map.get(@quota, :usage, 0))} / {format_metric(
              :messages_ingested,
              Map.get(@quota, :limit)
            )}
          </span>
        </div>
        <div class="w-full bg-base-200 rounded-full h-2 overflow-hidden">
          <div
            class={["h-2 rounded-full", quota_bar_class(Map.get(@quota, :state))]}
            style={"width: #{quota_bar_width(@quota)}%"}
          >
          </div>
        </div>
      </div>

      <dl class="grid grid-cols-2 sm:grid-cols-5 gap-4">
        <div :for={metric <- Flux.Metering.metrics()} class="rounded-lg border border-base-200 p-3">
          <dt class="text-xs text-base-content/60">{usage_metric_label(metric)}</dt>
          <dd class="text-lg font-semibold">{format_metric(metric, Map.get(@metrics, metric))}</dd>
        </div>
      </dl>
    </div>
    """
  end

  defp usage_metric_label(:messages_ingested), do: "Ingested"
  defp usage_metric_label(:messages_processed), do: "Processed"
  defp usage_metric_label(:sink_deliveries), do: "Sink deliveries"
  defp usage_metric_label(:active_pipelines), do: "Active pipelines"
  defp usage_metric_label(:pipeline_hours), do: "Pipeline hours"

  defp format_metric(_metric, nil), do: "∞"

  defp format_metric(:pipeline_hours, value) when is_number(value),
    do: :erlang.float_to_binary(value / 1, decimals: 1)

  defp format_metric(_metric, value) when is_integer(value), do: delimit(value)
  defp format_metric(_metric, value), do: to_string(value)

  # Group integer digits with commas (e.g. 12345 -> "12,345"); avoids a dep.
  defp delimit(value) when is_integer(value) do
    sign = if value < 0, do: "-", else: ""

    digits =
      value
      |> abs()
      |> Integer.to_string()
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.map_join(",", &Enum.join/1)
      |> String.reverse()

    sign <> digits
  end

  defp usage_pct(quota), do: quota |> Map.get(:pct, 0.0) |> round()

  defp quota_bar_width(quota) do
    quota |> Map.get(:pct, 0.0) |> min(100.0) |> max(0.0) |> Float.round(1)
  end

  defp quota_bar_class(:over), do: "bg-error"
  defp quota_bar_class(:warn), do: "bg-warning"
  defp quota_bar_class(_), do: "bg-primary"

  defp tier_badge_class(:enterprise), do: "badge-primary"
  defp tier_badge_class(:pro), do: "badge-secondary"
  defp tier_badge_class(_), do: "badge-ghost"

  defp license_value(nil), do: "—"
  defp license_value(value), do: to_string(value)

  defp format_expiry(nil), do: "Never"

  defp format_expiry(%DateTime{} = dt),
    do: Calendar.strftime(dt, "%Y-%m-%d")

  defp format_expiry(other), do: to_string(other)

  defp api_keys_section(assigns) do
    ~H"""
    <section class="card bg-base-100 shadow-sm border border-base-200">
      <div class="card-body">
        <div class="flex items-center justify-between">
          <h2 class="card-title text-base font-bold">
            <.icon name="hero-key" class="w-5 h-5" /> API Keys
          </h2>
        </div>
        <p class="text-sm text-base-content/60">
          Programmatic access to the REST API via the <code>X-API-Key</code> header.
          A key acts with the role you assign it.
        </p>

        <div
          :if={@revealed_key}
          id="revealed-api-key"
          class="mt-4 rounded-lg border border-amber-300 bg-amber-50 p-4"
        >
          <div class="flex items-start justify-between gap-2">
            <p class="text-sm font-semibold text-amber-900">
              Copy this key now — it will not be shown again.
            </p>
            <button
              type="button"
              phx-click="dismiss_api_key"
              class="btn btn-ghost btn-xs btn-circle"
              aria-label="Dismiss"
            >
              <.icon name="hero-x-mark" class="w-4 h-4" />
            </button>
          </div>
          <div class="mt-2 flex items-center gap-2">
            <input
              type="text"
              readonly
              value={@revealed_key}
              class="input input-sm input-bordered font-mono w-full"
            />
            <button
              type="button"
              id="copy-api-key"
              phx-hook=".CopyApiKey"
              data-key={@revealed_key}
              class="btn btn-sm"
            >
              Copy
            </button>
          </div>
        </div>

        <.form
          for={@api_key_form}
          id="api-key-form"
          phx-submit="create_api_key"
          class="mt-4 flex flex-col sm:flex-row gap-2 sm:items-end"
        >
          <.input field={@api_key_form[:name]} type="text" label="Name" placeholder="Production CI" />
          <.input
            field={@api_key_form[:role]}
            type="select"
            label="Role"
            options={[{"Admin", "admin"}, {"Member", "member"}, {"Viewer", "viewer"}]}
          />
          <.input
            :if={@scopes_enabled}
            field={@api_key_form[:scopes]}
            type="select"
            multiple
            label="Scopes"
            options={scope_options()}
          />
          <.input field={@api_key_form[:expires_at]} type="date" label="Expires (optional)" />
          <.button class="btn btn-primary">Create key</.button>
        </.form>
        <p :if={@scopes_enabled} class="text-xs text-base-content/50 mt-1">
          A key's access is the intersection of its role and its scopes.
        </p>
        <div :if={!@scopes_enabled} class="mt-2">
          <UpgradePrompt.upgrade_prompt feature={:api_key_scopes} size={:compact} />
        </div>

        <div class="mt-4 overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Name</th>
                <th>Key</th>
                <th>Role</th>
                <th>Scopes</th>
                <th>Last used</th>
                <th>Status</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={key <- @api_keys} id={"api-key-#{key.id}"}>
                <td class="font-medium">{key.name}</td>
                <td class="font-mono text-xs">{key.key_prefix}…</td>
                <td class="capitalize">{key.role}</td>
                <td class="text-xs">
                  <span
                    :for={scope <- Flux.Accounts.ApiKey.effective_scopes(key)}
                    class="badge badge-ghost badge-xs mr-1 whitespace-nowrap"
                  >
                    {scope}
                  </span>
                </td>
                <td class="text-sm text-base-content/60">{format_last_used(key.last_used_at)}</td>
                <td>
                  <span class={["badge badge-sm", api_key_status_class(key)]}>
                    {api_key_status(key)}
                  </span>
                </td>
                <td class="text-right">
                  <button
                    :if={Flux.Accounts.ApiKey.active?(key)}
                    type="button"
                    phx-click="revoke_api_key"
                    phx-value-id={key.id}
                    data-confirm={"Revoke #{key.name}? This cannot be undone."}
                    class="btn btn-ghost btn-xs text-error"
                  >
                    Revoke
                  </button>
                </td>
              </tr>
              <tr :if={@api_keys == []}>
                <td colspan="7" class="text-center text-base-content/50 py-6">
                  No API keys yet.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </section>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyApiKey">
      export default {
        mounted() {
          this.el.addEventListener("click", () => {
            navigator.clipboard?.writeText(this.el.dataset.key)
            const original = this.el.textContent
            this.el.textContent = "Copied!"
            setTimeout(() => { this.el.textContent = original }, 1500)
          })
        }
      }
    </script>
    """
  end

  defp api_key_status(key) do
    cond do
      Flux.Accounts.ApiKey.revoked?(key) -> "revoked"
      Flux.Accounts.ApiKey.expired?(key, DateTime.utc_now()) -> "expired"
      true -> "active"
    end
  end

  defp api_key_status_class(key) do
    case api_key_status(key) do
      "active" -> "badge-success"
      _ -> "badge-ghost"
    end
  end

  defp format_last_used(nil), do: "Never"
  defp format_last_used(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp new_api_key_form do
    to_form(
      %{
        "name" => "",
        "role" => "admin",
        "scopes" => Flux.Accounts.ApiKey.scopes(),
        "expires_at" => ""
      },
      as: :api_key
    )
  end

  defp scope_options, do: Enum.map(Flux.Accounts.ApiKey.scopes(), &{&1, &1})

  defp api_key_attrs(params) do
    params
    |> Map.take(["name", "role", "scopes"])
    |> put_expires_at(Map.get(params, "expires_at"))
  end

  defp put_expires_at(attrs, date) when date in [nil, ""], do: attrs

  defp put_expires_at(attrs, date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> Map.put(attrs, "expires_at", DateTime.new!(date, ~T[23:59:59]))
      _ -> attrs
    end
  end

  defp teams_section(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm border border-base-200">
      <div class="card-body">
        <div class="flex items-center justify-between">
          <h2 class="card-title">Teams</h2>
          <button
            type="button"
            phx-click="new_team"
            class="btn btn-primary btn-sm"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> New Team
          </button>
        </div>
        <div class="overflow-x-auto">
          <table class="table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Description</th>
                <th class="text-right">Actions</th>
              </tr>
            </thead>
            <tbody id="teams-list" phx-update="stream">
              <tr :for={{id, team} <- @streams[@stream_name]} id={id} class="hover">
                <td>{team.name}</td>
                <td class="max-w-xs truncate" title={team.description}>{team.description || "—"}</td>
                <td class="text-right">
                  <button
                    type="button"
                    phx-click="edit_team"
                    phx-value-id={team.id}
                    class="btn btn-ghost btn-sm"
                  >
                    <.icon name="hero-pencil" class="w-4 h-4" />
                  </button>
                  <button
                    type="button"
                    phx-click="delete_team"
                    phx-value-id={team.id}
                    class="btn btn-ghost btn-sm text-error"
                    data-confirm="Delete this team?"
                  >
                    <.icon name="hero-trash" class="w-4 h-4" />
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <%= if @team_form do %>
      <div class="modal modal-open" id="team-modal">
        <div class="modal-box">
          <.form
            for={@team_form}
            id="team-form"
            phx-submit="save_team"
            phx-change="validate_team"
            class="space-y-4"
          >
            <.input field={@team_form[:name]} type="text" label="Name" />
            <.input field={@team_form[:description]} type="textarea" label="Description (optional)" />
            <div class="modal-action">
              <button type="button" phx-click="clear_team_form" class="btn btn-ghost">
                Cancel
              </button>
              <button type="submit" class="btn btn-primary">Save</button>
            </div>
          </.form>
        </div>
        <div class="modal-backdrop" phx-click="clear_team_form"></div>
      </div>
    <% end %>
    """
  end

  defp members_section(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm border border-base-200">
      <div class="card-body">
        <div class="flex items-center justify-between">
          <h2 class="card-title">
            {if @rbac_mode == :org_centric, do: "Organization members", else: "Team members"}
          </h2>
          <button
            type="button"
            phx-click="new_member"
            class="btn btn-primary btn-sm"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> Add
          </button>
        </div>
        <div class="overflow-x-auto">
          <table class="table">
            <thead>
              <tr>
                <%= if @rbac_mode == :team_centric do %>
                  <th>Name</th>
                <% end %>
                <th>User</th>
                <%= if @rbac_mode == :team_centric do %>
                  <th>Team</th>
                <% end %>
                <th>Role</th>
                <th class="text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= for member <- @members do %>
                <.member_row member={member} rbac_mode={@rbac_mode} scope={@scope} />
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <%= if @member_form do %>
      <div class="modal modal-open" id="member-modal">
        <div class="modal-box">
          <.form
            for={@member_form}
            id="member-form"
            phx-submit="save_member"
            phx-change="validate_member"
            class="space-y-4"
          >
            <.input
              field={@member_form[:email]}
              type="text"
              label="Email"
              readonly={@editing_member_id != nil}
            />
            <%= if @rbac_mode == :team_centric do %>
              <.input field={@member_form[:first_name]} type="text" label="First name (optional)" />
              <.input field={@member_form[:last_name]} type="text" label="Last name (optional)" />
              <.input
                field={@member_form[:team_id]}
                type="select"
                label="Team"
                options={team_options(@teams)}
              />
            <% end %>
            <.input
              field={@member_form[:role]}
              type="select"
              label="Role"
              options={role_options(@rbac_mode)}
            />
            <div class="modal-action">
              <button type="button" phx-click="clear_member_form" class="btn btn-ghost">
                Cancel
              </button>
              <button type="submit" class="btn btn-primary">
                {if @editing_member_id, do: "Save", else: "Add"}
              </button>
            </div>
          </.form>
        </div>
        <div class="modal-backdrop" phx-click="clear_member_form"></div>
      </div>
    <% end %>
    """
  end

  defp member_row(assigns) do
    ~H"""
    <tr class={["hover", member_disabled?(@member) && "opacity-60"]}>
      <%= if @rbac_mode == :team_centric do %>
        <td>{member_display_name(@member)}</td>
      <% end %>
      <td>{user_email(@member)}</td>
      <%= if @rbac_mode == :team_centric do %>
        <td>{team_name(@member)}</td>
      <% end %>
      <td>
        <span class="badge badge-ghost">{@member.role}</span>
        <%= if member_disabled?(@member) do %>
          <span class="badge badge-warning badge-sm ml-1">Disabled</span>
        <% end %>
      </td>
      <td class="text-right">
        <%= if not member_disabled?(@member) do %>
          <button
            type="button"
            phx-click="edit_member"
            phx-value-id={member_id(@member)}
            phx-value-kind={@rbac_mode}
            class="btn btn-ghost btn-sm"
            title="Edit role"
          >
            <.icon name="hero-pencil" class="w-4 h-4" />
          </button>
          <%= if not member_is_current_user?(@member, @scope) do %>
            <button
              type="button"
              phx-click="disable_member"
              phx-value-id={member_id(@member)}
              phx-value-kind={@rbac_mode}
              class="btn btn-ghost btn-sm text-warning"
              title="Disable"
              data-confirm="Disable this member? They will lose access until re-enabled."
            >
              <.icon name="hero-no-symbol" class="w-4 h-4" />
            </button>
          <% end %>
        <% else %>
          <%= if member_is_current_user?(@member, @scope) do %>
            <span class="text-base-content/50 text-sm">(you)</span>
          <% else %>
            <button
              type="button"
              phx-click="enable_member"
              phx-value-id={member_id(@member)}
              phx-value-kind={@rbac_mode}
              class="btn btn-ghost btn-sm text-success"
              title="Re-enable"
            >
              <.icon name="hero-check-circle" class="w-4 h-4" />
            </button>
          <% end %>
        <% end %>
        <%= if not member_is_current_user?(@member, @scope) do %>
          <button
            type="button"
            phx-click="remove_member"
            phx-value-id={member_id(@member)}
            phx-value-kind={@rbac_mode}
            class="btn btn-ghost btn-sm text-error"
            data-confirm="Remove this member permanently?"
          >
            <.icon name="hero-trash" class="w-4 h-4" />
          </button>
        <% end %>
      </td>
    </tr>
    """
  end

  defp member_disabled?(%OrganizationMember{} = m), do: OrganizationMember.disabled?(m)
  defp member_disabled?(%TeamMember{} = m), do: TeamMember.disabled?(m)

  defp member_is_current_user?(member, %{user: %{id: user_id}}) do
    member_user_id(member) == user_id
  end

  defp member_user_id(%OrganizationMember{user_id: id}), do: id
  defp member_user_id(%TeamMember{user_id: id}), do: id

  defp member_display_name(%TeamMember{first_name: f, last_name: l}) do
    parts =
      [f, l]
      |> Enum.map(fn x -> if is_binary(x), do: String.trim(x), else: "" end)
      |> Enum.reject(&(&1 == ""))

    if parts == [], do: "—", else: Enum.join(parts, " ")
  end

  defp user_email(%OrganizationMember{user: %Ecto.Association.NotLoaded{} = _}), do: "—"
  defp user_email(%OrganizationMember{user: %{email: email}}), do: email
  defp user_email(%TeamMember{user: %Ecto.Association.NotLoaded{} = _}), do: "—"
  defp user_email(%TeamMember{user: %{email: email}}), do: email

  defp team_name(%TeamMember{team: %Ecto.Association.NotLoaded{} = _}), do: "—"
  defp team_name(%TeamMember{team: %{name: name}}), do: name

  defp member_id(%OrganizationMember{id: id}), do: id
  defp member_id(%TeamMember{id: id}), do: id

  defp team_options(teams), do: [{"Select team", ""} | Enum.map(teams, &{&1.name, &1.id})]

  defp role_options(:org_centric),
    do: [{"Admin", "admin"}, {"Member", "member"}, {"Viewer", "viewer"}]

  defp role_options(:team_centric),
    do: [{"Admin", "admin"}, {"Member", "member"}, {"Viewer", "viewer"}]

  @impl true
  def handle_event("activate_license", %{"license" => %{"token" => token}}, socket) do
    case token |> to_string() |> String.trim() |> activate_license() do
      {:ok, license} ->
        {:noreply,
         socket
         |> assign(:license, Map.put_new(license, :tier, Flux.License.tier()))
         |> assign(:node_states, Flux.License.node_states())
         |> assign(:node_capacity, Flux.License.node_capacity())
         |> assign(:license_form, to_form(%{"token" => ""}, as: :license))
         |> put_flash(:info, activation_message(license))}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Could not activate license: #{license_error(reason)}")}
    end
  end

  def handle_event("create_api_key", %{"api_key" => params}, socket) do
    org_id = socket.assigns.org_id

    case Accounts.create_api_key(org_id, api_key_attrs(params)) do
      {:ok, raw, _api_key} ->
        {:noreply,
         socket
         |> assign(:revealed_key, raw)
         |> assign(:api_keys, Accounts.list_api_keys(org_id))
         |> assign(:api_key_form, new_api_key_form())
         |> put_flash(:info, "API key created.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :api_key_form, to_form(changeset, as: :api_key))}
    end
  end

  def handle_event("revoke_api_key", %{"id" => id}, socket) do
    org_id = socket.assigns.org_id

    socket =
      case Accounts.revoke_api_key(id) do
        {:ok, _} ->
          socket
          |> assign(:api_keys, Accounts.list_api_keys(org_id))
          |> put_flash(:info, "API key revoked.")

        _ ->
          put_flash(socket, :error, "Could not revoke key.")
      end

    {:noreply, socket}
  end

  def handle_event("dismiss_api_key", _params, socket) do
    {:noreply, assign(socket, :revealed_key, nil)}
  end

  def handle_event("save_security_settings", %{"security" => %{"ip_allowlist" => text}}, socket) do
    scope = socket.assigns.current_scope

    if Permissions.can?(scope, :manage_security_settings) do
      entries = String.split(text, ~r/[\n,]/)

      case Security.update_settings(scope.organization_id, %{ip_allowlist: entries}) do
        {:ok, settings} ->
          {:noreply,
           socket
           |> assign(:security_settings, settings)
           |> assign(:security_form, security_form(settings))
           |> assign(:security_error, nil)
           |> put_flash(:info, "IP allowlist updated.")}

        {:error, changeset} ->
          timeout = socket.assigns.security_settings.session_timeout_minutes

          form =
            to_form(
              %{"ip_allowlist" => text, "session_timeout_minutes" => to_string(timeout)},
              as: :security
            )

          {:noreply,
           socket
           |> assign(:security_form, form)
           |> assign(:security_error, security_error(changeset))}
      end
    else
      {:noreply, put_flash(socket, :error, "You are not allowed to manage security settings.")}
    end
  end

  def handle_event(
        "save_session_timeout",
        %{"security" => %{"session_timeout_minutes" => minutes}},
        socket
      ) do
    scope = socket.assigns.current_scope

    if Permissions.can?(scope, :manage_security_settings) do
      case Security.update_settings(scope.organization_id, %{session_timeout_minutes: minutes}) do
        {:ok, settings} ->
          {:noreply,
           socket
           |> assign(:security_settings, settings)
           |> assign(:security_form, security_form(settings))
           |> put_flash(:info, "Session timeout updated.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Session timeout must be at least 1 hour.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You are not allowed to manage security settings.")}
    end
  end

  def handle_event("save_branding", %{"branding" => params}, socket) do
    scope = socket.assigns.current_scope

    # Re-checked here rather than trusted from the render: a hidden form is not
    # an access control, and entitlement can lapse between mount and submit.
    cond do
      not Permissions.can?(scope, :manage_branding) ->
        {:noreply, put_flash(socket, :error, "You are not allowed to manage branding.")}

      not Flux.Branding.entitled?() ->
        {:noreply, put_flash(socket, :error, "White-label branding requires Flux Enterprise.")}

      true ->
        attrs = Map.take(params, ["brand_name", "primary_color", "login_message"])

        case Flux.Branding.put(scope.organization_id, attrs) do
          {:ok, theme} ->
            {:noreply,
             socket
             |> assign(:branding, theme)
             |> assign(:branding_form, branding_form(theme))
             |> put_flash(:info, "Branding updated. Reload to see the new colours.")}

          {:error, errors} ->
            {:noreply,
             socket
             |> assign(
               :branding_form,
               to_form(params, as: :branding, errors: errors)
             )
             |> put_flash(:error, "Could not update branding.")}
        end
    end
  end

  def handle_event("save_password_policy", %{"security" => params}, socket) do
    scope = socket.assigns.current_scope

    if Permissions.can?(scope, :manage_security_settings) do
      attrs = %{
        password_min_length: params["password_min_length"],
        password_require_upper: params["password_require_upper"],
        password_require_lower: params["password_require_lower"],
        password_require_number: params["password_require_number"],
        password_require_special: params["password_require_special"],
        # Blank clears rotation (disabled); the changeset casts "" to nil.
        password_rotation_days: params["password_rotation_days"]
      }

      case Security.update_settings(scope.organization_id, attrs) do
        {:ok, settings} ->
          {:noreply,
           socket
           |> assign(:security_settings, settings)
           |> assign(:security_form, security_form(settings))
           |> put_flash(:info, "Password policy updated.")}

        {:error, changeset} ->
          {:noreply,
           socket
           |> assign(
             :security_form,
             to_form(Map.merge(socket.assigns.security_form.params, params), as: :security)
           )
           |> put_flash(:error, password_policy_error(changeset))}
      end
    else
      {:noreply, put_flash(socket, :error, "You are not allowed to manage security settings.")}
    end
  end

  def handle_event("save_mfa_enforcement", %{"security" => params}, socket) do
    scope = socket.assigns.current_scope

    if Permissions.can?(scope, :manage_security_settings) do
      # An unchecked checkbox is absent from params; default to "false".
      attrs = %{require_mfa: params["require_mfa"] || "false"}

      case Security.update_settings(scope.organization_id, attrs) do
        {:ok, settings} ->
          {:noreply,
           socket
           |> assign(:security_settings, settings)
           |> assign(:security_form, security_form(settings))
           |> put_flash(:info, "MFA enforcement updated.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not update MFA enforcement.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You are not allowed to manage security settings.")}
    end
  end

  def handle_event("clear_team_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:team_form, nil)
     |> assign(:editing_team_id, nil)}
  end

  def handle_event("clear_member_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:member_form, nil)
     |> assign(:editing_member_id, nil)}
  end

  def handle_event("new_team", _params, socket) do
    scope = socket.assigns.current_scope

    form =
      %Team{}
      |> Team.changeset(%{}, scope)
      |> to_form(as: "team")

    {:noreply, assign(socket, :team_form, form)}
  end

  def handle_event("edit_team", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    team = Structure.get_team!(scope, String.to_integer(id))

    form =
      team
      |> Team.changeset(%{"name" => team.name, "description" => team.description}, scope)
      |> to_form(as: "team")

    {:noreply,
     socket
     |> assign(:team_form, form)
     |> assign(:editing_team_id, team.id)}
  end

  def handle_event("validate_team", %{"team" => params}, socket) do
    scope = socket.assigns.current_scope

    team =
      (socket.assigns[:editing_team_id] &&
         Structure.get_team!(scope, socket.assigns.editing_team_id)) || %Team{}

    form =
      team
      |> Team.changeset(params, scope)
      |> Map.put(:action, :validate)
      |> to_form(as: "team")

    {:noreply, assign(socket, :team_form, form)}
  end

  def handle_event("save_team", %{"team" => params}, socket) do
    scope = socket.assigns.current_scope
    editing_id = socket.assigns[:editing_team_id]

    result =
      if editing_id do
        team = Structure.get_team!(scope, editing_id)
        Structure.update_team(scope, team, params)
      else
        Structure.create_team(scope, params)
      end

    case result do
      {:ok, _team} ->
        teams = Structure.list_teams(scope)

        {:noreply,
         socket
         |> assign(:team_form, nil)
         |> assign(:editing_team_id, nil)
         |> assign(:teams, teams)
         |> stream(:teams_stream, teams, reset: true)
         |> put_flash(:info, if(editing_id, do: "Team updated.", else: "Team created."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        form = to_form(changeset, as: "team")
        {:noreply, assign(socket, :team_form, form)}
    end
  end

  def handle_event("delete_team", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    team = Structure.get_team!(scope, String.to_integer(id))
    {:ok, _} = Structure.delete_team(scope, team)
    teams = Structure.list_teams(scope)

    {:noreply,
     socket
     |> assign(:teams, teams)
     |> stream(:teams_stream, teams, reset: true)
     |> put_flash(:info, "Team deleted.")}
  end

  def handle_event("new_member", _params, socket) do
    form =
      %{"email" => "", "first_name" => "", "last_name" => "", "team_id" => "", "role" => "member"}
      |> to_form(as: "member")

    {:noreply,
     socket
     |> assign(:member_form, form)
     |> assign(:editing_member_id, nil)}
  end

  def handle_event("edit_member", %{"id" => id, "kind" => "org_centric"}, socket) do
    om = Repo.get!(OrganizationMember, String.to_integer(id)) |> Repo.preload(:user)
    email = if om.user, do: om.user.email, else: ""

    form =
      %{"email" => email, "role" => om.role}
      |> to_form(as: "member")

    {:noreply,
     socket
     |> assign(:member_form, form)
     |> assign(:editing_member_id, {om.id, :org_centric})}
  end

  def handle_event("edit_member", %{"id" => id, "kind" => "team_centric"}, socket) do
    scope = socket.assigns.current_scope
    tm = Structure.get_team_member!(scope, String.to_integer(id))
    email = if tm.user, do: tm.user.email, else: ""

    form =
      %{
        "email" => email,
        "first_name" => tm.first_name || "",
        "last_name" => tm.last_name || "",
        "team_id" => to_string(tm.team_id),
        "role" => tm.role
      }
      |> to_form(as: "member")

    {:noreply,
     socket
     |> assign(:member_form, form)
     |> assign(:editing_member_id, {tm.id, :team_centric})}
  end

  def handle_event("validate_member", %{"member" => params}, socket) do
    form =
      params
      |> to_form(as: "member")

    {:noreply, assign(socket, :member_form, form)}
  end

  def handle_event("save_member", %{"member" => params}, socket) do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id
    rbac_mode = socket.assigns.rbac_mode
    editing = socket.assigns[:editing_member_id]

    result =
      if editing do
        {id, kind} = editing

        case kind do
          :org_centric ->
            om = Repo.get!(OrganizationMember, id)
            Structure.update_organization_member(om, %{role: params["role"] || "member"})

          :team_centric ->
            tm = Structure.get_team_member!(scope, id)
            team_id = params["team_id"] && String.to_integer(params["team_id"])

            attrs = %{
              role: params["role"] || "member",
              first_name:
                params["first_name"]
                |> to_string()
                |> String.trim()
                |> then(&if &1 == "", do: nil, else: &1),
              last_name:
                params["last_name"]
                |> to_string()
                |> String.trim()
                |> then(&if &1 == "", do: nil, else: &1)
            }

            attrs =
              if team_id do
                team = Structure.get_team!(scope, team_id)
                Map.put(attrs, :team_id, team.id)
              else
                attrs
              end

            Structure.update_team_member(tm, attrs)
        end
      else
        case rbac_mode do
          :org_centric ->
            email = String.trim(params["email"] || "")
            user = Accounts.get_user_by_email(email)

            if user do
              Structure.create_organization_member(%{
                organization_id: org_id,
                user_id: user.id,
                role: params["role"] || "member"
              })
            else
              {:error, "User not found with email #{email}"}
            end

          :team_centric ->
            email = String.trim(params["email"] || "")
            user = Accounts.get_user_by_email(email)
            team_id = params["team_id"] && String.to_integer(params["team_id"])

            if user && team_id do
              team = Structure.get_team!(scope, team_id)

              first =
                (params["first_name"] || "")
                |> to_string()
                |> String.trim()
                |> then(&if &1 == "", do: nil, else: &1)

              last =
                (params["last_name"] || "")
                |> to_string()
                |> String.trim()
                |> then(&if &1 == "", do: nil, else: &1)

              Structure.create_team_member(%{
                user_id: user.id,
                team_id: team.id,
                role: params["role"] || "member",
                first_name: first,
                last_name: last
              })
            else
              {:error, "User or team missing"}
            end
        end
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:member_form, nil)
         |> assign(:editing_member_id, nil)
         |> reload_members()
         |> put_flash(:info, if(editing, do: "Member updated.", else: "Member added."))}

      {:error, msg} when is_binary(msg) ->
        {:noreply, put_flash(socket, :error, msg)}

      {:error, %Ecto.Changeset{} = changeset} ->
        form = to_form(changeset, as: "member")
        {:noreply, assign(socket, :member_form, form)}
    end
  end

  # remove/disable/enable share the same shape across both RBAC modes: look the
  # member up by kind, guard against acting on your own account (except enable),
  # run the action, then reload the list. The org_centric/team_centric specifics
  # are isolated in the fetch_member/2 and *_member/1 helpers below.
  def handle_event("remove_member", %{"id" => id, "kind" => kind}, socket) do
    guarded_member_action(socket, id, kind, "remove", &delete_member/1, "Member removed.")
  end

  def handle_event("disable_member", %{"id" => id, "kind" => kind}, socket) do
    guarded_member_action(socket, id, kind, "disable", &disable_member/1, "Member disabled.")
  end

  def handle_event("enable_member", %{"id" => id, "kind" => kind}, socket) do
    member = fetch_member(socket, kind, id)
    {:ok, _} = enable_member(member)
    {:noreply, socket |> reload_members() |> put_flash(:info, "Member re-enabled.")}
  end

  # Runs `action` on the member unless it is the current user's own account, in
  # which case it refuses with a "You cannot <verb> your own account." flash.
  defp guarded_member_action(socket, id, kind, verb, action, success_message) do
    member = fetch_member(socket, kind, id)

    if own_account?(member, socket) do
      {:noreply, put_flash(socket, :error, "You cannot #{verb} your own account.")}
    else
      {:ok, _} = action.(member)
      {:noreply, socket |> reload_members() |> put_flash(:info, success_message)}
    end
  end

  defp fetch_member(_socket, "org_centric", id),
    do: Repo.get!(OrganizationMember, String.to_integer(id))

  defp fetch_member(socket, "team_centric", id),
    do: Structure.get_team_member!(socket.assigns.current_scope, String.to_integer(id))

  defp own_account?(member, socket),
    do: member_user_id(member) == socket.assigns.current_scope.user.id

  defp delete_member(%OrganizationMember{} = m), do: Structure.delete_organization_member(m)
  defp delete_member(%TeamMember{} = m), do: Structure.delete_team_member(m)

  defp disable_member(%OrganizationMember{} = m), do: Structure.disable_organization_member(m)
  defp disable_member(%TeamMember{} = m), do: Structure.disable_team_member(m)

  defp enable_member(%OrganizationMember{} = m), do: Structure.enable_organization_member(m)
  defp enable_member(%TeamMember{} = m), do: Structure.enable_team_member(m)

  defp reload_members(socket) do
    scope = socket.assigns.current_scope
    members = load_members(scope, scope.organization_id, socket.assigns.rbac_mode)
    assign(socket, :members, members)
  end
end
