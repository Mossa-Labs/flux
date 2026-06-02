defmodule Flux.StructureFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Flux.Structure` context.
  """

  @doc """
  Generate a unique organization slug.
  """
  def unique_organization_slug, do: "some slug#{System.unique_integer([:positive])}"

  @doc """
  Generate a organization.
  """
  def organization_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "some name",
        slug: unique_organization_slug()
      })

    {:ok, organization} = Flux.Structure.create_organization(scope, attrs)
    organization
  end

  @doc """
  Generate a team.
  """
  def team_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "some name"
      })

    {:ok, team} = Flux.Structure.create_team(scope, attrs)
    team
  end

  @doc """
  Generate a team_member. Requires a team and user (e.g. from scope); pass user_id and team_id in attrs
  or use the optional scope to create a team and use scope.user.
  """
  def team_member_fixture(attrs \\ %{}) do
    # Allow caller to pass user_id and team_id; otherwise create scope, org, team and use them
    base =
      case attrs do
        %{user_id: _uid, team_id: _tid} ->
          attrs

        _ ->
          scope = Flux.AccountsFixtures.user_scope_fixture()
          _org = organization_fixture(scope)
          # Ensure team has org for scope (team_fixture uses scope.organization_id)
          team = team_fixture(scope)
          Map.merge(attrs, %{user_id: scope.user.id, team_id: team.id})
      end

    {:ok, team_member} =
      base
      |> Enum.into(%{role: "member"})
      |> Flux.Structure.create_team_member()

    team_member
  end
end
