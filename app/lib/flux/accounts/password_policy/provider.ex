defmodule Flux.Accounts.PasswordPolicy.Provider do
  @moduledoc """
  Contract for per-organization password policy providers (MOS-590).

  Configurable password policy — raising the minimum length, requiring
  character-class complexity, and password rotation — is an Enterprise feature.
  The public repo ships only the facade (`Flux.Accounts.PasswordPolicy`), this
  contract, and `Flux.Accounts.PasswordPolicy.Providers.Community` — a no-op stub
  that strengthens nothing. The Enterprise edition overlays the real provider via
  `Flux.Accounts.PasswordPolicy.Registry.set_active/1` once `:password_policy` is
  entitled.

  The base invariants — `password` required, `min: 12`, `max: 128` — are enforced
  in `Flux.Accounts.User.validate_password/2` *before* this contract runs and are
  never bypassable. A provider may only **strengthen** the policy (raise the
  minimum, add complexity), never weaken it.
  """

  @type organization_id :: integer() | binary() | nil

  @doc """
  Applies the org's password policy to a password changeset.

  Runs after the base length rules. `organization_id` identifies whose policy to
  read (a provider reads it from `Flux.Security.get_settings/1`). Must be total —
  return the changeset unchanged when there is no org or no stronger policy.
  """
  @callback validate(Ecto.Changeset.t(), organization_id()) :: Ecto.Changeset.t()

  @doc """
  Whether the scope's user must rotate their password before continuing.

  Checked at login (see `FluxWeb.UserAuth`). Must be total — return `false`
  rather than raising when rotation is disabled or no password is set.
  """
  @callback expired?(Flux.Accounts.Scope.t()) :: boolean()
end
