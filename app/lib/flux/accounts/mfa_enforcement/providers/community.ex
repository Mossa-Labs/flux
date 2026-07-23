defmodule Flux.Accounts.MfaEnforcement.Providers.Community do
  @moduledoc """
  Community no-op MFA enforcement provider (MOS-591).

  Per-org "require MFA for all members" is an Enterprise feature. This stub never
  enforces — `enforced?/1` always returns `false` — so on a Community build members
  may enroll in MFA but are never *required* to. The Enterprise edition overlays the
  real provider once `:mfa_enforcement` is entitled.
  """

  @behaviour Flux.Accounts.MfaEnforcement.Provider

  @impl true
  def enforced?(_scope), do: false
end
