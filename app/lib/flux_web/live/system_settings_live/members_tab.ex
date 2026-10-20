defmodule FluxWeb.SystemSettingsLive.MembersTab do
  @moduledoc """
  The Members & teams tab of System Settings.
  """
  use FluxWeb, :html

  import FluxWeb.SystemSettingsLive.Components

  alias Flux.Structure.{OrganizationMember, TeamMember}

  attr :scope, :any, required: true
  attr :members, :list, required: true
  attr :teams, :list, required: true
  attr :rbac_mode, :atom, required: true
  attr :member_form, :any, default: nil
  attr :editing_member_id, :any, default: nil
  attr :team_form, :any, default: nil
  attr :streams, :any, required: true

  def members_tab(assigns) do
    ~H"""
    <div class="grid gap-6 xl:grid-cols-3 xl:items-start">
      <.members_card
        class="xl:col-span-2"
        scope={@scope}
        members={@members}
        rbac_mode={@rbac_mode}
      />
      <.teams_card teams_stream={@streams.teams_stream} />
    </div>

    <.team_modal :if={@team_form} form={@team_form} />
    <.member_modal
      :if={@member_form}
      form={@member_form}
      teams={@teams}
      rbac_mode={@rbac_mode}
      editing_member_id={@editing_member_id}
    />
    """
  end

  attr :class, :any, default: nil
  attr :scope, :any, required: true
  attr :members, :list, required: true
  attr :rbac_mode, :atom, required: true

  defp members_card(assigns) do
    ~H"""
    <.settings_card
      id="members-card"
      class={@class}
      title={if @rbac_mode == :org_centric, do: "Organization members", else: "Team members"}
      icon="hero-users"
    >
      <:actions>
        <button type="button" phx-click="new_member" class="btn btn-primary btn-sm">
          <.icon name="hero-plus" class="size-4" /> Add member
        </button>
      </:actions>

      <div class="-mx-2 overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr class="text-base-content/60">
              <th>Member</th>
              <th :if={@rbac_mode == :team_centric}>Team</th>
              <th>Role</th>
              <th>Status</th>
              <th><span class="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody>
            <.member_row
              :for={member <- @members}
              member={member}
              rbac_mode={@rbac_mode}
              scope={@scope}
            />
          </tbody>
        </table>
      </div>
    </.settings_card>
    """
  end

  attr :member, :any, required: true
  attr :rbac_mode, :atom, required: true
  attr :scope, :any, required: true

  defp member_row(assigns) do
    assigns =
      assigns
      |> assign(:you?, member_is_current_user?(assigns.member, assigns.scope))
      |> assign(:disabled?, member_disabled?(assigns.member))

    ~H"""
    <tr class={["border-base-content/5", @disabled? && "opacity-60"]}>
      <td>
        <p :if={@rbac_mode == :team_centric} class="font-medium">
          {member_display_name(@member)}
        </p>
        <p class={[@rbac_mode == :team_centric && "text-xs text-base-content/60"]}>
          {user_email(@member)}
          <span :if={@you?} class="text-base-content/50">(you)</span>
        </p>
      </td>
      <td :if={@rbac_mode == :team_centric}>{team_name(@member)}</td>
      <td class="capitalize">{@member.role}</td>
      <td>
        <span :if={@disabled?} class="badge badge-sm badge-ghost">Disabled</span>
        <span :if={!@disabled?} class="badge badge-sm badge-success badge-soft">Active</span>
      </td>
      <td class="whitespace-nowrap text-right">
        <button
          :if={!@disabled?}
          type="button"
          phx-click="edit_member"
          phx-value-id={member_id(@member)}
          phx-value-kind={@rbac_mode}
          class="btn btn-ghost btn-sm btn-square"
          title="Edit role"
          aria-label="Edit role"
        >
          <.icon name="hero-pencil" class="size-4" />
        </button>
        <button
          :if={!@disabled? and !@you?}
          type="button"
          phx-click="disable_member"
          phx-value-id={member_id(@member)}
          phx-value-kind={@rbac_mode}
          class="btn btn-ghost btn-sm btn-square text-warning"
          title="Disable"
          aria-label="Disable"
          data-confirm="Disable this member? They will lose access until re-enabled."
        >
          <.icon name="hero-no-symbol" class="size-4" />
        </button>
        <button
          :if={@disabled? and !@you?}
          type="button"
          phx-click="enable_member"
          phx-value-id={member_id(@member)}
          phx-value-kind={@rbac_mode}
          class="btn btn-ghost btn-sm btn-square text-success"
          title="Re-enable"
          aria-label="Re-enable"
        >
          <.icon name="hero-check-circle" class="size-4" />
        </button>
        <button
          :if={!@you?}
          type="button"
          phx-click="remove_member"
          phx-value-id={member_id(@member)}
          phx-value-kind={@rbac_mode}
          class="btn btn-ghost btn-sm btn-square text-error"
          title="Remove"
          aria-label="Remove"
          data-confirm="Remove this member permanently?"
        >
          <.icon name="hero-trash" class="size-4" />
        </button>
      </td>
    </tr>
    """
  end

  attr :teams_stream, :any, required: true

  defp teams_card(assigns) do
    ~H"""
    <.settings_card id="teams-card" title="Teams" icon="hero-user-group">
      <:actions>
        <button type="button" phx-click="new_team" class="btn btn-sm btn-outline">
          <.icon name="hero-plus" class="size-4" /> New team
        </button>
      </:actions>

      <ul id="teams-list" phx-update="stream" class="space-y-2">
        <li id="teams-empty" class="hidden py-4 text-center text-sm text-base-content/60 only:block">
          No teams yet.
        </li>
        <li
          :for={{id, team} <- @teams_stream}
          id={id}
          class="flex items-start gap-2 rounded-box border border-base-content/5 bg-base-300 p-3"
        >
          <div class="min-w-0 flex-1">
            <p class="truncate font-medium">{team.name}</p>
            <p class="line-clamp-2 text-xs text-base-content/60" title={team.description}>
              {team.description || "No description"}
            </p>
          </div>
          <button
            type="button"
            phx-click="edit_team"
            phx-value-id={team.id}
            class="btn btn-ghost btn-sm btn-square"
            aria-label={"Edit #{team.name}"}
          >
            <.icon name="hero-pencil" class="size-4" />
          </button>
          <button
            type="button"
            phx-click="delete_team"
            phx-value-id={team.id}
            class="btn btn-ghost btn-sm btn-square text-error"
            aria-label={"Delete #{team.name}"}
            data-confirm="Delete this team?"
          >
            <.icon name="hero-trash" class="size-4" />
          </button>
        </li>
      </ul>
    </.settings_card>
    """
  end

  attr :form, :any, required: true

  defp team_modal(assigns) do
    ~H"""
    <div class="modal modal-open" id="team-modal">
      <div class="modal-box">
        <.form
          for={@form}
          id="team-form"
          phx-submit="save_team"
          phx-change="validate_team"
          class="space-y-4"
        >
          <.input field={@form[:name]} type="text" label="Name" />
          <.input field={@form[:description]} type="textarea" label="Description (optional)" />
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
    """
  end

  attr :form, :any, required: true
  attr :teams, :list, required: true
  attr :rbac_mode, :atom, required: true
  attr :editing_member_id, :any, default: nil

  defp member_modal(assigns) do
    ~H"""
    <div class="modal modal-open" id="member-modal">
      <div class="modal-box">
        <.form
          for={@form}
          id="member-form"
          phx-submit="save_member"
          phx-change="validate_member"
          class="space-y-4"
        >
          <.input
            field={@form[:email]}
            type="text"
            label="Email"
            readonly={@editing_member_id != nil}
          />
          <%= if @rbac_mode == :team_centric do %>
            <.input field={@form[:first_name]} type="text" label="First name (optional)" />
            <.input field={@form[:last_name]} type="text" label="Last name (optional)" />
            <.input field={@form[:team_id]} type="select" label="Team" options={team_options(@teams)} />
            <p :if={@teams == []} class="text-sm text-warning">
              Create a team first: in team mode every member belongs to one.
            </p>
          <% end %>
          <.input field={@form[:role]} type="select" label="Role" options={role_options()} />
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

  # The same three roles in both RBAC modes.
  defp role_options, do: [{"Admin", "admin"}, {"Member", "member"}, {"Viewer", "viewer"}]
end
