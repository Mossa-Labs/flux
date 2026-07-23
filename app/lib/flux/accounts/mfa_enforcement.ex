defmodule Flux.Accounts.MfaEnforcement do
  @moduledoc """
  Facade over the active `Flux.Accounts.MfaEnforcement.Provider` (MOS-591).

  Per-user TOTP MFA is Community (see `Flux.Accounts.Mfa`). Whether an organization
  can *require* MFA of every member is the Enterprise-gated `:mfa_enforcement`
  feature. The login flow and protected mounts route through this module rather than
  calling a provider directly: the Community build resolves to
  `Flux.Accounts.MfaEnforcement.Providers.Community` (never enforces); the Enterprise
  edition overlays the real provider via
  `Flux.Accounts.MfaEnforcement.Registry.set_active/1`.

  Entitlement is re-checked here on every call, so a license downgrade immediately
  stops enforcement — members can never be locked out by a stale "required" flag.
  """

  alias Flux.Accounts.MfaEnforcement.Registry

  @doc """
  Whether the scope's org requires MFA of all members *and* is entitled to enforce it.

  Returns `false` unless `:mfa_enforcement` is entitled, regardless of the stored
  per-org setting — so losing the entitlement transparently disables enforcement.
  """
  @spec enforced?(Flux.Accounts.Scope.t()) :: boolean()
  def enforced?(scope) do
    Flux.License.has_feature?(:mfa_enforcement) and Registry.active().enforced?(scope)
  end
end
