defmodule Flux.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `Flux.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use as authorization, or to
  ensure specific code paths can only be access for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias Flux.Accounts.User
  alias Flux.Repo
  alias Flux.Structure.Organization
  alias Flux.Structure.OrganizationMember
  alias Flux.Structure.Team
  alias Flux.Structure.TeamMember

  import Ecto.Query

  defstruct user: nil, organization_id: nil, organization_role: nil

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given. Loads the user's default organization and
  role according to :rbac_mode (:org_centric from organization_members,
  :team_centric from teams/team_members, with fallback when no teams).
  """
  def for_user(%User{} = user) do
    case Flux.RBAC.mode() do
      :org_centric -> for_user_org_centric(user)
      :team_centric -> for_user_team_centric(user)
    end
  end

  def for_user(nil), do: nil

  @doc """
  Returns whether the user is allowed to log in.

  A user can log in if they have at least one active (non-disabled) membership
  in the current rbac_mode, or if they own an organization. Disabled members
  with no other access cannot log in.
  """
  def user_can_log_in?(nil), do: false

  def user_can_log_in?(%User{} = user) do
    case Flux.RBAC.mode() do
      :org_centric ->
        user_has_org_access?(user.id) or user_owns_org?(user.id)

      :team_centric ->
        get_default_org_and_role_from_teams(user.id) != nil or user_owns_org?(user.id)
    end
  end

  defp user_owns_org?(user_id) do
    Organization
    |> where([o], o.user_id == ^user_id)
    |> limit(1)
    |> select([o], o.id)
    |> Repo.one() != nil
  end

  defp user_has_org_access?(user_id) do
    get_default_org_and_role_from_members(user_id) != nil
  end

  defp for_user_org_centric(user) do
    case get_default_org_and_role_from_members(user.id) do
      {org_id, role} ->
        %__MODULE__{user: user, organization_id: org_id, organization_role: role}

      nil ->
        # Fallback: orgs where user is owner (organizations.user_id)
        org_id =
          Organization
          |> where([o], o.user_id == ^user.id)
          |> order_by([o], asc: o.inserted_at)
          |> limit(1)
          |> select([o], o.id)
          |> Repo.one()

        %__MODULE__{user: user, organization_id: org_id, organization_role: org_id && "owner"}
    end
  end

  defp get_default_org_and_role_from_members(user_id) do
    OrganizationMember
    |> where([om], om.user_id == ^user_id and is_nil(om.disabled_at))
    |> order_by([om], asc: om.inserted_at)
    |> limit(1)
    |> select([om], {om.organization_id, om.role})
    |> Repo.one()
  end

  defp for_user_team_centric(user) do
    case get_default_org_and_role_from_teams(user.id) do
      {org_id, role} when is_integer(org_id) ->
        role = maybe_owner_for_org(user.id, org_id, role)
        %__MODULE__{user: user, organization_id: org_id, organization_role: role}

      nil ->
        # No teams: fallback to first org (e.g. single-tenant / seeds)
        org_id =
          Organization
          |> order_by([o], asc: o.inserted_at)
          |> limit(1)
          |> select([o], o.id)
          |> Repo.one()

        role = if org_id, do: maybe_owner_for_org(user.id, org_id, "member"), else: nil
        %__MODULE__{user: user, organization_id: org_id, organization_role: role}
    end
  end

  # In team_centric, org creator (organizations.user_id) is treated as owner
  defp maybe_owner_for_org(user_id, org_id, team_role) do
    case Repo.get(Organization, org_id) do
      %Organization{user_id: ^user_id} -> "owner"
      _ -> team_role
    end
  end

  defp get_default_org_and_role_from_teams(user_id) do
    # Distinct orgs from user's team memberships (excluding disabled); pick first org and best role in that org
    query =
      from tm in TeamMember,
        join: t in Team,
        on: tm.team_id == t.id,
        where:
          tm.user_id == ^user_id and not is_nil(t.organization_id) and is_nil(tm.disabled_at),
        order_by: [asc: t.inserted_at],
        limit: 1,
        select: {t.organization_id, tm.role}

    case Repo.one(query) do
      {org_id, role} -> {org_id, best_role_for_org(user_id, org_id, role)}
      nil -> nil
    end
  end

  defp best_role_for_org(user_id, org_id, first_role) do
    # Best role among all active team memberships in this org (admin > member > viewer)
    roles =
      from tm in TeamMember,
        join: t in Team,
        on: tm.team_id == t.id,
        where: tm.user_id == ^user_id and t.organization_id == ^org_id and is_nil(tm.disabled_at),
        select: tm.role

    Repo.all(roles)
    |> Enum.reduce(first_role, fn r, best ->
      if role_rank(r) > role_rank(best), do: r, else: best
    end)
  end

  defp role_rank("admin"), do: 3
  defp role_rank("member"), do: 2
  defp role_rank("viewer"), do: 1
  defp role_rank(_), do: 0
end
