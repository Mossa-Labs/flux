defmodule FluxWeb.SystemSettingsLive do
  @moduledoc """
  Owner-only system settings: manage teams and users.
  Renders 403 with 20-second redirect when not authorized.
  """
  use FluxWeb, :live_view

  alias Flux.Accounts
  alias Flux.Permissions
  alias Flux.Repo
  alias Flux.Structure
  alias Flux.Structure.{OrganizationMember, Team, TeamMember}

  @redirect_after_ms 20_000
  @tick_ms 1_000

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    authorized = scope && Permissions.can?(scope, :view_system_settings)

    if authorized do
      org_id = scope.organization_id
      rbac_mode = Application.get_env(:flux, :rbac_mode, :team_centric)
      teams = if org_id, do: Structure.list_teams(scope), else: []
      members = load_members(scope, org_id, rbac_mode)

      {:ok,
       socket
       |> assign(:active_tab, :system_settings)
       |> assign(:page_title, "System Settings")
       |> assign(:authorized, true)
       |> assign(:org_id, org_id)
       |> assign(:rbac_mode, rbac_mode)
       |> assign(:teams, teams)
       |> assign(:members, members)
       |> assign(:team_form, nil)
       |> assign(:member_form, nil)
       |> assign(:editing_member_id, nil)
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
          teams={@teams}
          members={@members}
          rbac_mode={@rbac_mode}
          team_form={@team_form}
          member_form={@member_form}
          editing_member_id={@editing_member_id}
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
        <h1 class="text-2xl font-bold bg-gradient-to-r from-indigo-500 via-purple-500 to-pink-500 bg-clip-text text-transparent">
          System Settings
        </h1>
        <p class="text-base-content/60 mt-1">Manage teams and users for your organization</p>
      </div>

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
      <% else %>
        <p class="text-base-content/60">
          No organization in scope. Create or select an organization first.
        </p>
      <% end %>
    </div>
    """
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
    tm = Structure.get_team_member!(scope, String.to_integer(id)) |> Repo.preload([:user, :team])
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
        members = load_members(scope, org_id, rbac_mode)

        {:noreply,
         socket
         |> assign(:member_form, nil)
         |> assign(:editing_member_id, nil)
         |> assign(:members, members)
         |> put_flash(:info, if(editing, do: "Member updated.", else: "Member added."))}

      {:error, msg} when is_binary(msg) ->
        {:noreply, put_flash(socket, :error, msg)}

      {:error, %Ecto.Changeset{} = changeset} ->
        form = to_form(changeset, as: "member")
        {:noreply, assign(socket, :member_form, form)}
    end
  end

  def handle_event("remove_member", %{"id" => id, "kind" => "org_centric"}, socket) do
    om = Repo.get!(OrganizationMember, String.to_integer(id))

    if om.user_id == socket.assigns.current_scope.user.id do
      {:noreply, put_flash(socket, :error, "You cannot remove your own account.")}
    else
      {:ok, _} = Structure.delete_organization_member(om)
      members = Structure.list_organization_members(socket.assigns.org_id)

      {:noreply,
       socket
       |> assign(:members, members)
       |> put_flash(:info, "Member removed.")}
    end
  end

  def handle_event("remove_member", %{"id" => id, "kind" => "team_centric"}, socket) do
    scope = socket.assigns.current_scope
    tm = Structure.get_team_member!(scope, String.to_integer(id))

    if tm.user_id == scope.user.id do
      {:noreply, put_flash(socket, :error, "You cannot remove your own account.")}
    else
      {:ok, _} = Structure.delete_team_member(tm)
      members = Structure.list_team_members(scope)

      {:noreply,
       socket
       |> assign(:members, members)
       |> put_flash(:info, "Member removed.")}
    end
  end

  def handle_event("disable_member", %{"id" => id, "kind" => "org_centric"}, socket) do
    om = Repo.get!(OrganizationMember, String.to_integer(id))

    if om.user_id == socket.assigns.current_scope.user.id do
      {:noreply, put_flash(socket, :error, "You cannot disable your own account.")}
    else
      {:ok, _} = Structure.disable_organization_member(om)
      members = Structure.list_organization_members(socket.assigns.org_id)

      {:noreply,
       socket
       |> assign(:members, members)
       |> put_flash(:info, "Member disabled.")}
    end
  end

  def handle_event("disable_member", %{"id" => id, "kind" => "team_centric"}, socket) do
    scope = socket.assigns.current_scope
    tm = Structure.get_team_member!(scope, String.to_integer(id))

    if tm.user_id == scope.user.id do
      {:noreply, put_flash(socket, :error, "You cannot disable your own account.")}
    else
      {:ok, _} = Structure.disable_team_member(tm)
      members = Structure.list_team_members(scope)

      {:noreply,
       socket
       |> assign(:members, members)
       |> put_flash(:info, "Member disabled.")}
    end
  end

  def handle_event("enable_member", %{"id" => id, "kind" => "org_centric"}, socket) do
    om = Repo.get!(OrganizationMember, String.to_integer(id))
    {:ok, _} = Structure.enable_organization_member(om)
    members = Structure.list_organization_members(socket.assigns.org_id)

    {:noreply,
     socket
     |> assign(:members, members)
     |> put_flash(:info, "Member re-enabled.")}
  end

  def handle_event("enable_member", %{"id" => id, "kind" => "team_centric"}, socket) do
    scope = socket.assigns.current_scope
    tm = Structure.get_team_member!(scope, String.to_integer(id))
    {:ok, _} = Structure.enable_team_member(tm)
    members = Structure.list_team_members(scope)

    {:noreply,
     socket
     |> assign(:members, members)
     |> put_flash(:info, "Member re-enabled.")}
  end
end
