defmodule Flux.PermissionsTest do
  use ExUnit.Case, async: true

  alias Flux.Accounts.Scope
  alias Flux.Permissions

  defp scope_with_role(role) do
    %Scope{organization_role: role, user: %Flux.Accounts.User{id: 1}, organization_id: 1}
  end

  defp scope_with_no_role do
    %Scope{organization_role: nil, user: %Flux.Accounts.User{id: 1}, organization_id: 1}
  end

  describe "can?/3 with nil organization_role" do
    test "denies all actions" do
      scope = scope_with_no_role()

      refute Permissions.can?(scope, :view_organization)
      refute Permissions.can?(scope, :manage_organization)
      refute Permissions.can?(scope, :view_pipelines)
      refute Permissions.can?(scope, :create_pipeline)
      refute Permissions.can?(scope, :view_dashboard)
      refute Permissions.can?(scope, :view_system_settings)
    end
  end

  describe "can?/3 :manage_organization" do
    test "allowed for owner and admin" do
      assert Permissions.can?(scope_with_role("owner"), :manage_organization)
      assert Permissions.can?(scope_with_role("admin"), :manage_organization)
    end

    test "denied for member and viewer" do
      refute Permissions.can?(scope_with_role("member"), :manage_organization)
      refute Permissions.can?(scope_with_role("viewer"), :manage_organization)
    end
  end

  describe "can?/3 :view_organization" do
    test "allowed for all roles" do
      assert Permissions.can?(scope_with_role("owner"), :view_organization)
      assert Permissions.can?(scope_with_role("admin"), :view_organization)
      assert Permissions.can?(scope_with_role("member"), :view_organization)
      assert Permissions.can?(scope_with_role("viewer"), :view_organization)
    end
  end

  describe "can?/3 :manage_teams" do
    test "allowed for owner and admin" do
      assert Permissions.can?(scope_with_role("owner"), :manage_teams)
      assert Permissions.can?(scope_with_role("admin"), :manage_teams)
    end

    test "denied for member and viewer" do
      refute Permissions.can?(scope_with_role("member"), :manage_teams)
      refute Permissions.can?(scope_with_role("viewer"), :manage_teams)
    end
  end

  describe "can?/3 :view_teams" do
    test "allowed for all roles" do
      assert Permissions.can?(scope_with_role("owner"), :view_teams)
      assert Permissions.can?(scope_with_role("admin"), :view_teams)
      assert Permissions.can?(scope_with_role("member"), :view_teams)
      assert Permissions.can?(scope_with_role("viewer"), :view_teams)
    end
  end

  describe "can?/3 :manage_team_members" do
    test "allowed for owner and admin" do
      assert Permissions.can?(scope_with_role("owner"), :manage_team_members)
      assert Permissions.can?(scope_with_role("admin"), :manage_team_members)
    end

    test "denied for member and viewer" do
      refute Permissions.can?(scope_with_role("member"), :manage_team_members)
      refute Permissions.can?(scope_with_role("viewer"), :manage_team_members)
    end
  end

  describe "can?/3 :view_pipelines" do
    test "allowed for all roles" do
      assert Permissions.can?(scope_with_role("owner"), :view_pipelines)
      assert Permissions.can?(scope_with_role("admin"), :view_pipelines)
      assert Permissions.can?(scope_with_role("member"), :view_pipelines)
      assert Permissions.can?(scope_with_role("viewer"), :view_pipelines)
    end
  end

  describe "can?/3 :create_pipeline" do
    test "allowed for owner, admin, member" do
      assert Permissions.can?(scope_with_role("owner"), :create_pipeline)
      assert Permissions.can?(scope_with_role("admin"), :create_pipeline)
      assert Permissions.can?(scope_with_role("member"), :create_pipeline)
    end

    test "denied for viewer" do
      refute Permissions.can?(scope_with_role("viewer"), :create_pipeline)
    end
  end

  describe "can?/3 :edit_pipeline" do
    test "allowed for owner, admin, member" do
      assert Permissions.can?(scope_with_role("owner"), :edit_pipeline)
      assert Permissions.can?(scope_with_role("admin"), :edit_pipeline)
      assert Permissions.can?(scope_with_role("member"), :edit_pipeline)
    end

    test "denied for viewer" do
      refute Permissions.can?(scope_with_role("viewer"), :edit_pipeline)
    end
  end

  describe "can?/3 :delete_pipeline" do
    test "allowed for owner and admin" do
      assert Permissions.can?(scope_with_role("owner"), :delete_pipeline)
      assert Permissions.can?(scope_with_role("admin"), :delete_pipeline)
    end

    test "denied for member and viewer" do
      refute Permissions.can?(scope_with_role("member"), :delete_pipeline)
      refute Permissions.can?(scope_with_role("viewer"), :delete_pipeline)
    end
  end

  describe "can?/3 :run_pipeline" do
    test "allowed for owner, admin, member" do
      assert Permissions.can?(scope_with_role("owner"), :run_pipeline)
      assert Permissions.can?(scope_with_role("admin"), :run_pipeline)
      assert Permissions.can?(scope_with_role("member"), :run_pipeline)
    end

    test "denied for viewer" do
      refute Permissions.can?(scope_with_role("viewer"), :run_pipeline)
    end
  end

  describe "can?/3 :view_sinks" do
    test "allowed for all roles" do
      assert Permissions.can?(scope_with_role("owner"), :view_sinks)
      assert Permissions.can?(scope_with_role("admin"), :view_sinks)
      assert Permissions.can?(scope_with_role("member"), :view_sinks)
      assert Permissions.can?(scope_with_role("viewer"), :view_sinks)
    end
  end

  describe "can?/3 :create_sink" do
    test "allowed for owner, admin, member" do
      assert Permissions.can?(scope_with_role("owner"), :create_sink)
      assert Permissions.can?(scope_with_role("admin"), :create_sink)
      assert Permissions.can?(scope_with_role("member"), :create_sink)
    end

    test "denied for viewer" do
      refute Permissions.can?(scope_with_role("viewer"), :create_sink)
    end
  end

  describe "can?/3 :edit_sink" do
    test "allowed for owner, admin, member" do
      assert Permissions.can?(scope_with_role("owner"), :edit_sink)
      assert Permissions.can?(scope_with_role("admin"), :edit_sink)
      assert Permissions.can?(scope_with_role("member"), :edit_sink)
    end

    test "denied for viewer" do
      refute Permissions.can?(scope_with_role("viewer"), :edit_sink)
    end
  end

  describe "can?/3 :delete_sink" do
    test "allowed for owner and admin" do
      assert Permissions.can?(scope_with_role("owner"), :delete_sink)
      assert Permissions.can?(scope_with_role("admin"), :delete_sink)
    end

    test "denied for member and viewer" do
      refute Permissions.can?(scope_with_role("member"), :delete_sink)
      refute Permissions.can?(scope_with_role("viewer"), :delete_sink)
    end
  end

  describe "can?/3 :view_members" do
    test "allowed for all roles" do
      assert Permissions.can?(scope_with_role("owner"), :view_members)
      assert Permissions.can?(scope_with_role("admin"), :view_members)
      assert Permissions.can?(scope_with_role("member"), :view_members)
      assert Permissions.can?(scope_with_role("viewer"), :view_members)
    end
  end

  describe "can?/3 :invite_member" do
    test "allowed for owner and admin" do
      assert Permissions.can?(scope_with_role("owner"), :invite_member)
      assert Permissions.can?(scope_with_role("admin"), :invite_member)
    end

    test "denied for member and viewer" do
      refute Permissions.can?(scope_with_role("member"), :invite_member)
      refute Permissions.can?(scope_with_role("viewer"), :invite_member)
    end
  end

  describe "can?/3 :change_member_role" do
    test "allowed for owner and admin" do
      assert Permissions.can?(scope_with_role("owner"), :change_member_role)
      assert Permissions.can?(scope_with_role("admin"), :change_member_role)
    end

    test "denied for member and viewer" do
      refute Permissions.can?(scope_with_role("member"), :change_member_role)
      refute Permissions.can?(scope_with_role("viewer"), :change_member_role)
    end
  end

  describe "can?/3 :remove_member" do
    test "allowed for owner and admin" do
      assert Permissions.can?(scope_with_role("owner"), :remove_member)
      assert Permissions.can?(scope_with_role("admin"), :remove_member)
    end

    test "denied for member and viewer" do
      refute Permissions.can?(scope_with_role("member"), :remove_member)
      refute Permissions.can?(scope_with_role("viewer"), :remove_member)
    end
  end

  describe "can?/3 :view_dashboard" do
    test "allowed for all roles" do
      assert Permissions.can?(scope_with_role("owner"), :view_dashboard)
      assert Permissions.can?(scope_with_role("admin"), :view_dashboard)
      assert Permissions.can?(scope_with_role("member"), :view_dashboard)
      assert Permissions.can?(scope_with_role("viewer"), :view_dashboard)
    end
  end

  describe "can?/3 :view_system_settings" do
    test "allowed for owner only" do
      assert Permissions.can?(scope_with_role("owner"), :view_system_settings)
    end

    test "denied for admin, member, and viewer" do
      refute Permissions.can?(scope_with_role("admin"), :view_system_settings)
      refute Permissions.can?(scope_with_role("member"), :view_system_settings)
      refute Permissions.can?(scope_with_role("viewer"), :view_system_settings)
    end
  end

  describe "can?/3 unknown action" do
    test "denied for all roles" do
      refute Permissions.can?(scope_with_role("owner"), :unknown_action)
      refute Permissions.can?(scope_with_role("admin"), :unknown_action)
      refute Permissions.can?(scope_with_role("member"), :unknown_action)
      refute Permissions.can?(scope_with_role("viewer"), :unknown_action)
    end
  end

  describe "can?/3 with resource argument" do
    test "passes resource through to permission check" do
      scope = scope_with_role("owner")
      assert Permissions.can?(scope, :edit_pipeline, %{id: 42})
    end

    test "resource does not affect permission logic" do
      viewer = scope_with_role("viewer")
      refute Permissions.can?(viewer, :edit_pipeline, %{id: 42})
    end
  end
end
