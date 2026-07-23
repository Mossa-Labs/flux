defmodule Flux.Accounts.MfaEnforcement.Provider do
  @moduledoc """
  Contract for per-organization MFA enforcement providers (MOS-591).

  Per-user TOTP MFA is Community. Whether an organization can *require* MFA of all
  its members is the Enterprise-gated `:mfa_enforcement` feature. The public repo
  ships only the facade (`Flux.Accounts.MfaEnforcement`), this contract, and
  `Flux.Accounts.MfaEnforcement.Providers.Community` — a no-op stub that never
  enforces. The Enterprise edition overlays the real provider via
  `Flux.Accounts.MfaEnforcement.Registry.set_active/1` once `:mfa_enforcement` is
  entitled.
  """

  @doc """
  Whether the scope's organization requires every member to have MFA enabled.

  Checked after login and on protected mounts. Must be total — return `false`
  rather than raising when there is no org in scope or enforcement is disabled.
  Implementations must also treat a lost entitlement as "not enforced" so a
  license downgrade can never leave members locked out.
  """
  @callback enforced?(Flux.Accounts.Scope.t()) :: boolean()
end
