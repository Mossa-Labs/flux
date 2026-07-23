defmodule Flux.Accounts.PasswordPolicy do
  @moduledoc """
  Facade over the active `Flux.Accounts.PasswordPolicy.Provider` (MOS-590).

  Password validation and the login flow route through this module rather than
  calling a provider directly. Configurable password policy (raising the minimum
  length, character-class complexity, rotation) is an Enterprise feature: the
  Community build resolves to `Flux.Accounts.PasswordPolicy.Providers.Community`
  (a no-op stub); the Enterprise edition overlays the real provider via
  `Flux.Accounts.PasswordPolicy.Registry.set_active/1` once `:password_policy` is
  entitled.

  The base rules (`required`, `min: 12`, `max: 128`) are enforced in
  `Flux.Accounts.User.validate_password/2` before `validate/2` runs, so an
  ungated build always keeps the min-12 default.
  """

  alias Flux.Accounts.PasswordPolicy.Provider
  alias Flux.Accounts.PasswordPolicy.Registry

  @doc """
  Applies `organization_id`'s password policy to a password changeset.

  See `Flux.Accounts.PasswordPolicy.Provider.validate/2`.
  """
  @spec validate(Ecto.Changeset.t(), Provider.organization_id()) :: Ecto.Changeset.t()
  def validate(changeset, organization_id) do
    Registry.active().validate(changeset, organization_id)
  end

  @doc """
  Whether the scope's user must rotate their password before continuing.

  See `Flux.Accounts.PasswordPolicy.Provider.expired?/1`.
  """
  @spec expired?(Flux.Accounts.Scope.t()) :: boolean()
  def expired?(scope) do
    Registry.active().expired?(scope)
  end
end
