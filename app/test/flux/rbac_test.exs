defmodule Flux.RBACTest do
  # async: false — mutates :rbac_mode config and swaps the license provider.
  use ExUnit.Case, async: false

  import Flux.LicenseHelpers

  setup do
    prior = Application.get_env(:flux, :rbac_mode)

    on_exit(fn ->
      if prior,
        do: Application.put_env(:flux, :rbac_mode, prior),
        else: Application.delete_env(:flux, :rbac_mode)
    end)

    :ok
  end

  test "defaults to :team_centric" do
    Application.delete_env(:flux, :rbac_mode)
    assert Flux.RBAC.mode() == :team_centric
  end

  test "stays :team_centric when org_centric configured but :org_rbac not licensed" do
    Application.put_env(:flux, :rbac_mode, :org_centric)
    # Community tier (default) is not entitled to :org_rbac
    assert Flux.RBAC.mode() == :team_centric
    refute Flux.RBAC.org_centric?()
  end

  test "is :org_centric when configured AND :org_rbac licensed (Pro+)" do
    Application.put_env(:flux, :rbac_mode, :org_centric)

    # :org_rbac is entitled from the Pro tier up.
    with_license_tier(:pro, fn ->
      assert Flux.RBAC.mode() == :org_centric
      assert Flux.RBAC.org_centric?()
    end)
  end

  test "stays :team_centric on a licensed build when configured team_centric" do
    Application.put_env(:flux, :rbac_mode, :team_centric)

    with_license_tier(:enterprise, fn ->
      assert Flux.RBAC.mode() == :team_centric
    end)
  end
end
