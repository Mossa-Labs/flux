defmodule FluxWeb.SystemSettingsLive.MembersTab do
  @moduledoc """
  Teams and members management for System Settings.
  """
  use FluxWeb, :html

  alias Flux.Structure.{OrganizationMember, TeamMember}

  def teams_section(assigns) do
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

  def members_section(assigns) do
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

  @doc false
  def member_user_id(%OrganizationMember{user_id: id}), do: id
  def member_user_id(%TeamMember{user_id: id}), do: id

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
end
