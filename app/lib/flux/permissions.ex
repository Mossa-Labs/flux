defmodule Flux.Permissions do
  @moduledoc """
  Role-based permission checks. Use `can?/3` with the current scope and action.

  Roles (strongest to weakest): owner, admin, member, viewer.
  When scope has no organization_role (e.g. no org), all actions are denied.
  """

  alias Flux.Accounts.Scope

  @doc """
  Returns whether the given scope can perform the action (optionally on a resource).

  ## Examples

      can?(scope, :view_pipelines)
      can?(scope, :edit_pipeline, pipeline)
  """
  def can?(scope, action, resource \\ nil)

  def can?(%Scope{organization_role: nil}, _action, _resource), do: false

  def can?(%Scope{organization_role: role}, action, resource) when is_binary(role) do
    allowed?(role, action, resource)
  end

  defp allowed?(role, action, resource) do
    case {action, resource} do
      # Organization
      {:manage_organization, _} -> role in ~w(owner admin)
      {:view_organization, _} -> role in ~w(owner admin member viewer)
      # Teams
      {:manage_teams, _} -> role in ~w(owner admin)
      {:view_teams, _} -> role in ~w(owner admin member viewer)
      {:manage_team_members, _} -> role in ~w(owner admin)
      # Pipelines
      {:view_pipelines, _} -> role in ~w(owner admin member viewer)
      {:create_pipeline, _} -> role in ~w(owner admin member)
      {:edit_pipeline, _} -> role in ~w(owner admin member)
      {:delete_pipeline, _} -> role in ~w(owner admin)
      {:run_pipeline, _} -> role in ~w(owner admin member)
      # Sinks
      {:view_sinks, _} -> role in ~w(owner admin member viewer)
      {:create_sink, _} -> role in ~w(owner admin member)
      {:edit_sink, _} -> role in ~w(owner admin member)
      {:delete_sink, _} -> role in ~w(owner admin)
      # Members (org members when org_centric)
      {:view_members, _} -> role in ~w(owner admin member viewer)
      {:invite_member, _} -> role in ~w(owner admin)
      {:change_member_role, _} -> role in ~w(owner admin)
      {:remove_member, _} -> role in ~w(owner admin)
      # Dashboard / general
      {:view_dashboard, _} -> role in ~w(owner admin member viewer)
      # System settings (owner only)
      {:view_system_settings, _} -> role == "owner"
      # Audit log (owner only) — Enterprise-gated at the LiveView/API layer
      {:view_audit_log, _} -> role == "owner"
      # Fallback: deny unknown actions
      {_, _} -> false
    end
  end
end
