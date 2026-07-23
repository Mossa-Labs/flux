defmodule Flux.Accounts.MfaEnforcementTest do
  # async: false — mutates the global enforcement Registry and license provider.
  use ExUnit.Case, async: false

  import Flux.LicenseHelpers

  alias Flux.Accounts.MfaEnforcement
  alias Flux.Accounts.MfaEnforcement.Registry
  alias Flux.Accounts.Scope

  defmodule AlwaysProvider do
    @behaviour Flux.Accounts.MfaEnforcement.Provider
    def enforced?(_scope), do: true
  end

  setup do
    original = Registry.active()
    on_exit(fn -> Registry.set_active(original) end)
    :ok
  end

  @scope %Scope{organization_id: 1}

  test "community tier never enforces, even with a would-enforce provider active" do
    Registry.set_active(AlwaysProvider)
    # Default community tier → :mfa_enforcement not entitled.
    refute MfaEnforcement.enforced?(@scope)
  end

  test "enterprise tier delegates to the active provider" do
    Registry.set_active(AlwaysProvider)

    with_license_tier(:enterprise, fn ->
      assert MfaEnforcement.enforced?(@scope)
    end)
  end

  test "the Community stub provider never enforces, even when entitled" do
    Registry.set_active(MfaEnforcement.Providers.Community)

    with_license_tier(:enterprise, fn ->
      refute MfaEnforcement.enforced?(@scope)
    end)
  end
end
