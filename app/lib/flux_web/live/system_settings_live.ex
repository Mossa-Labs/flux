defmodule FluxWeb.SystemSettingsLive do
  @moduledoc """
  Owner-only system settings: licensing, members and teams, API keys, security
  and branding, one tab each.

  The tab lives in the URL (`?tab=security`), so every tab is deep-linkable and
  the back button moves between them. All state and every event handler stay in
  this LiveView; the tab modules under `system_settings_live/` only render.

  Renders 403 with 20-second redirect when not authorized.
  """
  use FluxWeb, :live_view

  alias Flux.Accounts
  alias Flux.Permissions
  alias Flux.Repo
  alias Flux.Security
  alias Flux.Structure
  alias Flux.Structure.{OrganizationMember, Team, TeamMember}

  alias FluxWeb.SystemSettingsLive.{
    ApiKeysTab,
    BrandingTab,
    Components,
    GeneralTab,
    LicenseCard,
    MembersTab,
    SecurityTab
  }

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
       # :active_tab is the sidebar's key; the page's own tab is :settings_tab,
       # set for real by handle_params/3.
       |> assign(:active_tab, :system_settings)
       |> assign(:settings_tab, :general)
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
       |> assign(:editing_team_id, nil)
       |> assign(:member_form, nil)
       |> assign(:editing_member_id, nil)
       |> assign(:api_keys, if(org_id, do: Accounts.list_api_keys(org_id), else: []))
       |> assign(:api_key_form, new_api_key_form())
       |> assign(:revealed_key, nil)
       |> assign_entitlements()
       |> assign_branding(org_id)
       # accept: is a client-side hint only — the real check is the provider's
       # signature validation. max_file_size IS enforced server-side, and matches
       # the cap the stored bytes are budgeted against.
       |> allow_upload(:logo,
         accept: ~w(.png),
         max_entries: 1,
         max_file_size: 256_000
       )
       # PNG for the favicon too. ICO exists for Internet Explorer, retired in
       # 2022; every browser that can run this app takes a PNG icon, and a second
       # format would mean a second validator path for no living client.
       |> allow_upload(:favicon,
         accept: ~w(.png),
         max_entries: 1,
         max_file_size: 256_000
       )
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

  # An unauthorized visitor gets the same 403 whatever ?tab= says, and nothing
  # here may load data on their behalf.
  @impl true
  def handle_params(_params, _uri, %{assigns: %{authorized: false}} = socket),
    do: {:noreply, socket}

  def handle_params(params, _uri, socket) do
    tab = Components.tab_from_params(params)

    {:noreply,
     socket
     |> leave_tab(socket.assigns.settings_tab, tab)
     |> enter_tab(tab)
     |> assign(:settings_tab, tab)
     |> assign(:page_title, page_title(tab))}
  end

  defp leave_tab(socket, same, same), do: socket

  defp leave_tab(socket, from, _to) do
    socket
    # A modal belongs to the tab that opened it; the back button must not leave
    # one floating over another tab.
    |> assign(team_form: nil, editing_team_id: nil, member_form: nil, editing_member_id: nil)
    |> then(&if from == :branding, do: cancel_staged_uploads(&1), else: &1)
  end

  # Stream items are dropped from the socket once rendered, and the teams list
  # is not in the DOM on any other tab, so whatever mount streamed is gone by
  # the time someone arrives here from General. Re-send it on every entry.
  defp enter_tab(socket, :members),
    do: stream(socket, :teams_stream, socket.assigns.teams, reset: true)

  # Cheap, and the roster is the one thing on this page that changes underneath
  # it (a rolling restart), so coming back to General shows the current state.
  defp enter_tab(%{assigns: %{settings_tab: from}} = socket, :general) when from != :general do
    socket
    |> assign(:node_states, Flux.License.node_states())
    |> assign(:node_capacity, Flux.License.node_capacity())
  end

  defp enter_tab(socket, _tab), do: socket

  # A file staged on Branding and then abandoned would otherwise still hold the
  # single upload slot when the user comes back, and the next pick would fail
  # with "too many files" against an input that shows nothing.
  defp cancel_staged_uploads(socket) do
    Enum.reduce([:logo, :favicon], socket, fn name, acc ->
      Enum.reduce(acc.assigns.uploads[name].entries, acc, &cancel_upload(&2, name, &1.ref))
    end)
  end

  defp page_title(:general), do: "System Settings"
  defp page_title(tab), do: "#{Components.tab_label(tab)} · System Settings"

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

  # Which gated sections render their form rather than an upgrade prompt. Read
  # again after an activation: with tabs, the prompts on other tabs would
  # otherwise keep advertising features the new license has just unlocked.
  defp assign_entitlements(socket) do
    socket
    |> assign(:api_key_scopes_enabled, Flux.License.has_feature?(:api_key_scopes))
    |> assign(:password_policy_enabled, Flux.License.has_feature?(:password_policy))
    |> assign(:mfa_enforcement_enabled, Flux.License.has_feature?(:mfa_enforcement))
    |> assign(:branding_enabled, Flux.Branding.entitled?())
    |> assign(:usage_metering_enabled, usage_metering_enabled?())
  end

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

  # Consumes a staged logo, if one was chosen. No entry means the operator was
  # editing text only, which must not clear an existing logo.
  #
  # consume_uploaded_entries deletes the temp file once the callback returns, so
  # a rejection has to become a message rather than something retryable — and the
  # bytes are handed straight to the provider, which decides what they are. The
  # entry's client_type and client_name are never trusted or stored.
  defp save_assets(socket, org_id, theme) do
    Enum.reduce_while([:logo, :favicon], {:ok, theme}, fn kind, {:ok, acc} ->
      case save_asset(socket, org_id, kind, acc) do
        {:ok, theme} -> {:cont, {:ok, theme}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp save_asset(socket, org_id, kind, theme) do
    case uploaded_entries(socket, kind) do
      {[], _} ->
        {:ok, theme}

      _ ->
        socket
        |> consume_uploaded_entries(kind, fn %{path: path}, _entry ->
          {:ok, Flux.Branding.put_asset(org_id, kind, File.read!(path))}
        end)
        |> List.first()
    end
  end

  defp branding_error_message(errors) do
    cond do
      reason = Keyword.get(errors, :logo) -> "Logo #{reason}."
      reason = Keyword.get(errors, :favicon) -> "Favicon #{reason}."
      true -> "Could not update branding."
    end
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
        <div class="max-w-6xl space-y-6">
          <header class="space-y-1">
            <h1 class="text-2xl font-bold tracking-tight text-base-content">System Settings</h1>
            <p class="text-base-content/60">
              Licensing, access, security and branding for this Flux deployment.
            </p>
          </header>

          <Components.settings_tabs
            current={@settings_tab}
            attention={attention_tabs(@license, @node_states, @node_capacity)}
          />

          <div id="settings-panel" aria-label={Components.tab_label(@settings_tab)}>
            <%= cond do %>
              <% @settings_tab == :general -> %>
                <GeneralTab.general_tab
                  license={@license}
                  activation_supported={@activation_supported}
                  license_form={@license_form}
                  node_states={@node_states}
                  node_capacity={@node_capacity}
                  usage_metering_enabled={@usage_metering_enabled}
                  usage={@usage}
                />
              <% is_nil(@org_id) -> %>
                <Components.org_required />
              <% @settings_tab == :members -> %>
                <MembersTab.members_tab
                  scope={@current_scope}
                  members={@members}
                  teams={@teams}
                  rbac_mode={@rbac_mode}
                  member_form={@member_form}
                  editing_member_id={@editing_member_id}
                  team_form={@team_form}
                  streams={@streams}
                />
              <% @settings_tab == :api_keys -> %>
                <ApiKeysTab.api_keys_tab
                  api_keys={@api_keys}
                  api_key_form={@api_key_form}
                  revealed_key={@revealed_key}
                  scopes_enabled={@api_key_scopes_enabled}
                />
              <% @settings_tab == :security -> %>
                <SecurityTab.security_tab
                  form={@security_form}
                  error={@security_error}
                  password_policy_enabled={@password_policy_enabled}
                  mfa_enforcement_enabled={@mfa_enforcement_enabled}
                />
              <% @settings_tab == :branding -> %>
                <BrandingTab.branding_tab
                  enabled={@branding_enabled}
                  branding={@branding}
                  form={@branding_form}
                  uploads={@uploads}
                />
            <% end %>
          </div>
        </div>
      <% else %>
        <.forbidden_content seconds_left={@seconds_left} />
      <% end %>
    </div>
    """
  end

  # General is the only tab that can need attention: an expiry banner, nodes
  # that disagree, or more nodes than the license covers.
  defp attention_tabs(license, node_states, node_capacity) do
    if LicenseCard.needs_attention?(license, node_states, node_capacity),
      do: [:general],
      else: []
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
         |> assign_entitlements()
         |> assign(:usage, load_usage(socket.assigns.org_id))
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
          # Keep every other field of the shared form. Rebuilding it from the
          # allowlist alone blanked the password-policy and MFA forms, and saving
          # either of those next would then write the blanks over real settings.
          form =
            to_form(Map.merge(socket.assigns.security_form.params, %{"ip_allowlist" => text}),
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

  # Only needed so live_file_input can stage an entry; the text fields are
  # validated by the provider on submit.
  def handle_event("validate_branding", _params, socket), do: {:noreply, socket}

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

        with {:ok, theme} <- Flux.Branding.put(scope.organization_id, attrs),
             {:ok, theme} <- save_assets(socket, scope.organization_id, theme) do
          {:noreply,
           socket
           |> assign(:branding, theme)
           |> assign(:branding_form, branding_form(theme))
           |> put_flash(:info, "Branding updated. Reload to see the new colours.")}
        else
          {:error, errors} ->
            {:noreply,
             socket
             |> assign(:branding_form, to_form(params, as: :branding, errors: errors))
             |> put_flash(:error, branding_error_message(errors))}
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
    do: MembersTab.member_user_id(member) == socket.assigns.current_scope.user.id

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
