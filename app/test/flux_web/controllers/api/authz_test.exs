defmodule FluxWeb.API.AuthzTest do
  # async: false — require_feature/2 swaps the global license provider.
  use ExUnit.Case, async: false

  import Flux.LicenseHelpers

  alias FluxWeb.API.Authz
  alias Flux.Accounts.Scope

  defp conn_with(assigns) do
    %Plug.Conn{assigns: assigns}
  end

  describe "authorize/2" do
    test "allows an action the org role permits" do
      conn = conn_with(%{current_scope: %Scope{organization_role: "member"}})
      assert :ok = Authz.authorize(conn, :create_pipeline)
    end

    test "forbids an action the org role does not permit" do
      conn = conn_with(%{current_scope: %Scope{organization_role: "viewer"}})
      assert {:error, :forbidden} = Authz.authorize(conn, :create_pipeline)
    end

    test "forbids when there is no current_scope" do
      assert {:error, :forbidden} = Authz.authorize(conn_with(%{}), :view_pipelines)
    end
  end

  describe "require_scope/2" do
    test "allows when the required scope is granted" do
      conn = conn_with(%{api_scopes: ["pipelines:read", "pipelines:write"]})
      assert :ok = Authz.require_scope(conn, "pipelines:write")
    end

    test "forbids when the required scope is not granted" do
      conn = conn_with(%{api_scopes: ["pipelines:read"]})
      assert {:error, :forbidden} = Authz.require_scope(conn, "pipelines:write")
    end

    test "forbids when api_scopes assign is missing" do
      assert {:error, :forbidden} = Authz.require_scope(conn_with(%{}), "pipelines:read")
    end
  end

  describe "require_feature/2" do
    test "allows a licensed Pro feature" do
      with_license_tier(:pro, fn ->
        assert :ok = Authz.require_feature(%Plug.Conn{}, :advanced_ai)
      end)
    end

    test "forbids a Pro feature on the community tier" do
      with_license_tier(:community, fn ->
        assert {:error, :forbidden} = Authz.require_feature(%Plug.Conn{}, :advanced_ai)
      end)
    end
  end
end
