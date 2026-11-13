defmodule Flux.MfaEnforcementTestProvider do
  @moduledoc """
  Test-only MFA enforcement provider that always enforces. Swap it in with
  `Flux.Accounts.MfaEnforcement.Registry.set_active/1` (with `:mfa_enforcement`
  entitled) and restore the Community provider afterwards.
  """

  @behaviour Flux.Accounts.MfaEnforcement.Provider

  @impl true
  def enforced?(_scope), do: true
end
