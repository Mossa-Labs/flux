defmodule Flux.Structure do
  @moduledoc """
  The Structure context.
  """

  import Ecto.Query, warn: false
  alias Flux.Repo

  alias Flux.Structure.Organization
  alias Flux.Structure.OrganizationMember
  alias Flux.Accounts.Scope

  @doc """
  Subscribes to scoped notifications about any organization changes.

  The broadcasted messages match the pattern:

    * `{:created, %Organization{}}`
    * `{:updated, %Organization{}}`
    * `{:deleted, %Organization{}}`

  """
  def subscribe_organizations(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(Flux.PubSub, "user:#{key}:organizations")
  end

  defp broadcast_organization(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(Flux.PubSub, "user:#{key}:organizations", message)
  end

  @doc """
  Returns the list of organizations.

  ## Examples

      iex> list_organizations(scope)
      [%Organization{}, ...]

  """
  def list_organizations(%Scope{} = scope) do
    from(o in Organization, where: o.user_id == ^scope.user.id) |> Repo.all()
  end

  @doc """
  Gets a single organization.

  Raises `Ecto.NoResultsError` if the Organization does not exist.

  ## Examples

      iex> get_organization!(scope, 123)
      %Organization{}

      iex> get_organization!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_organization!(%Scope{} = scope, id) do
    Repo.get_by!(Organization, id: id, user_id: scope.user.id)
  end

  @doc """
  Creates a organization.

  ## Examples

      iex> create_organization(scope, %{field: value})
      {:ok, %Organization{}}

      iex> create_organization(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_organization(%Scope{} = scope, attrs) do
    with {:ok, organization = %Organization{}} <-
           %Organization{}
           |> Organization.changeset(attrs, scope)
           |> Repo.insert(),
         :ok <- maybe_add_organization_owner(organization, scope) do
      broadcast_organization(scope, {:created, organization})
      {:ok, organization}
    end
  end

  defp maybe_add_organization_owner(%Organization{id: org_id}, %Scope{user: user}) do
    if Application.get_env(:flux, :rbac_mode, :team_centric) == :org_centric do
      case %OrganizationMember{}
           |> OrganizationMember.changeset(%{
             organization_id: org_id,
             user_id: user.id,
             role: "owner"
           })
           |> Repo.insert() do
        {:ok, _} -> :ok
        {:error, _} = err -> err
      end
    else
      :ok
    end
  end

  @doc """
  Returns the organization membership for a user in an org, when :rbac_mode is :org_centric.
  """
  def get_organization_member(organization_id, user_id) do
    Repo.get_by(OrganizationMember, organization_id: organization_id, user_id: user_id)
  end

  @doc """
  Returns all organization members for an organization (for :org_centric mode).
  """
  def list_organization_members(organization_id) do
    from(om in OrganizationMember,
      where: om.organization_id == ^organization_id,
      order_by: [asc: om.inserted_at],
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  Creates an organization member (for :org_centric mode).
  """
  def create_organization_member(attrs) do
    %OrganizationMember{}
    |> OrganizationMember.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an organization member.
  """
  def update_organization_member(%OrganizationMember{} = om, attrs) do
    om
    |> OrganizationMember.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an organization member.
  """
  def delete_organization_member(%OrganizationMember{} = om) do
    Repo.delete(om)
  end

  @doc """
  Soft-disables an organization member (sets disabled_at). Disabled members are excluded from scope/role resolution.
  """
  def disable_organization_member(%OrganizationMember{} = om) do
    om
    |> OrganizationMember.changeset(%{disabled_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @doc """
  Re-enables an organization member (clears disabled_at).
  """
  def enable_organization_member(%OrganizationMember{} = om) do
    om
    |> OrganizationMember.changeset(%{disabled_at: nil})
    |> Repo.update()
  end

  @doc """
  Updates a organization.

  ## Examples

      iex> update_organization(scope, organization, %{field: new_value})
      {:ok, %Organization{}}

      iex> update_organization(scope, organization, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_organization(%Scope{} = scope, %Organization{} = organization, attrs) do
    true = organization.user_id == scope.user.id

    with {:ok, organization = %Organization{}} <-
           organization
           |> Organization.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_organization(scope, {:updated, organization})
      {:ok, organization}
    end
  end

  @doc """
  Deletes a organization.

  ## Examples

      iex> delete_organization(scope, organization)
      {:ok, %Organization{}}

      iex> delete_organization(scope, organization)
      {:error, %Ecto.Changeset{}}

  """
  def delete_organization(%Scope{} = scope, %Organization{} = organization) do
    true = organization.user_id == scope.user.id

    with {:ok, organization = %Organization{}} <-
           Repo.delete(organization) do
      broadcast_organization(scope, {:deleted, organization})
      {:ok, organization}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking organization changes.

  ## Examples

      iex> change_organization(scope, organization)
      %Ecto.Changeset{data: %Organization{}}

  """
  def change_organization(%Scope{} = scope, %Organization{} = organization, attrs \\ %{}) do
    true = organization.user_id == scope.user.id

    Organization.changeset(organization, attrs, scope)
  end

  alias Flux.Structure.Team
  alias Flux.Accounts.Scope

  @doc """
  Subscribes to scoped notifications about any team changes.

  The broadcasted messages match the pattern:

    * `{:created, %Team{}}`
    * `{:updated, %Team{}}`
    * `{:deleted, %Team{}}`

  """
  def subscribe_teams(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(Flux.PubSub, "user:#{key}:teams")
  end

  defp broadcast_team(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(Flux.PubSub, "user:#{key}:teams", message)
  end

  @doc """
  Returns the list of teams for the current scope (scoped by organization when present).

  ## Examples

      iex> list_teams(scope)
      [%Team{}, ...]

  """
  def list_teams(%Scope{organization_id: org_id} = _scope) when is_integer(org_id) do
    from(t in Team, where: t.organization_id == ^org_id) |> Repo.all()
  end

  def list_teams(%Scope{} = scope) do
    from(t in Team, where: t.user_id == ^scope.user.id) |> Repo.all()
  end

  @doc """
  Gets a single team.

  Raises `Ecto.NoResultsError` if the Team does not exist.

  ## Examples

      iex> get_team!(scope, 123)
      %Team{}

      iex> get_team!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_team!(%Scope{organization_id: org_id} = _scope, id) when is_integer(org_id) do
    Repo.get_by!(Team, id: id, organization_id: org_id)
  end

  def get_team!(%Scope{} = scope, id) do
    Repo.get_by!(Team, id: id, user_id: scope.user.id)
  end

  @doc """
  Creates a team.

  ## Examples

      iex> create_team(scope, %{field: value})
      {:ok, %Team{}}

      iex> create_team(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_team(%Scope{} = scope, attrs) do
    with {:ok, team = %Team{}} <-
           %Team{}
           |> Team.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_team(scope, {:created, team})
      {:ok, team}
    end
  end

  @doc """
  Updates a team.

  ## Examples

      iex> update_team(scope, team, %{field: new_value})
      {:ok, %Team{}}

      iex> update_team(scope, team, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_team(%Scope{} = scope, %Team{} = team, attrs) do
    true = team.user_id == scope.user.id or scope.organization_role == "owner"

    with {:ok, team = %Team{}} <-
           team
           |> Team.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_team(scope, {:updated, team})
      {:ok, team}
    end
  end

  @doc """
  Deletes a team.

  ## Examples

      iex> delete_team(scope, team)
      {:ok, %Team{}}

      iex> delete_team(scope, team)
      {:error, %Ecto.Changeset{}}

  """
  def delete_team(%Scope{} = scope, %Team{} = team) do
    true = team.user_id == scope.user.id or scope.organization_role == "owner"

    with {:ok, team = %Team{}} <-
           Repo.delete(team) do
      broadcast_team(scope, {:deleted, team})
      {:ok, team}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking team changes.

  ## Examples

      iex> change_team(scope, team)
      %Ecto.Changeset{data: %Team{}}

  """
  def change_team(%Scope{} = scope, %Team{} = team, attrs \\ %{}) do
    true = team.user_id == scope.user.id or scope.organization_role == "owner"

    Team.changeset(team, attrs, scope)
  end

  alias Flux.Structure.TeamMember

  @doc """
  Returns the list of team_members (unscoped). Prefer list_team_members/1 when you have a scope.

  ## Examples

      iex> list_team_members()
      [%TeamMember{}, ...]

  """
  def list_team_members do
    Repo.all(TeamMember)
  end

  @doc """
  Returns team members for teams in the scope's current organization.
  """
  def list_team_members(%Scope{organization_id: org_id}) when is_integer(org_id) do
    import Ecto.Query

    from(tm in TeamMember,
      join: t in Team,
      on: tm.team_id == t.id,
      where: t.organization_id == ^org_id,
      order_by: [asc: t.name, asc: tm.id],
      preload: [:user, :team]
    )
    |> Repo.all()
  end

  def list_team_members(_scope), do: list_team_members()

  @doc """
  Gets a single team_member (unscoped). Prefer get_team_member!/2 when you have a scope.

  Raises `Ecto.NoResultsError` if the Team member does not exist.

  ## Examples

      iex> get_team_member!(123)
      %TeamMember{}

      iex> get_team_member!(456)
      ** (Ecto.NoResultsError)

  """
  def get_team_member!(id), do: Repo.get!(TeamMember, id)

  @doc """
  Gets a single team_member, ensuring the member's team is in the scope's organization.
  """
  def get_team_member!(%Scope{organization_id: org_id}, id) when is_integer(org_id) do
    tm = Repo.get!(TeamMember, id)
    team = Repo.get!(Team, tm.team_id)
    if team.organization_id == org_id, do: tm, else: raise(Ecto.NoResultsError)
  end

  def get_team_member!(_scope, id), do: get_team_member!(id)

  @doc """
  Creates a team_member.

  ## Examples

      iex> create_team_member(%{field: value})
      {:ok, %TeamMember{}}

      iex> create_team_member(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_team_member(attrs) do
    %TeamMember{}
    |> TeamMember.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a team_member.

  ## Examples

      iex> update_team_member(team_member, %{field: new_value})
      {:ok, %TeamMember{}}

      iex> update_team_member(team_member, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_team_member(%TeamMember{} = team_member, attrs) do
    team_member
    |> TeamMember.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a team_member.

  ## Examples

      iex> delete_team_member(team_member)
      {:ok, %TeamMember{}}

      iex> delete_team_member(team_member)
      {:error, %Ecto.Changeset{}}

  """
  def delete_team_member(%TeamMember{} = team_member) do
    Repo.delete(team_member)
  end

  @doc """
  Soft-disables a team member (sets disabled_at). Disabled members are excluded from scope/role resolution.
  """
  def disable_team_member(%TeamMember{} = team_member) do
    team_member
    |> TeamMember.changeset(%{disabled_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @doc """
  Re-enables a team member (clears disabled_at).
  """
  def enable_team_member(%TeamMember{} = team_member) do
    team_member
    |> TeamMember.changeset(%{disabled_at: nil})
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking team_member changes.

  ## Examples

      iex> change_team_member(team_member)
      %Ecto.Changeset{data: %TeamMember{}}

  """
  def change_team_member(%TeamMember{} = team_member, attrs \\ %{}) do
    TeamMember.changeset(team_member, attrs)
  end
end
