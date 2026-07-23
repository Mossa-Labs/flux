defmodule Flux.Accounts.PasswordPolicy.Providers.Community do
  @moduledoc """
  Community no-op password policy provider (MOS-590).

  Configurable password policy is an Enterprise feature. The base rules
  (`required`, `min: 12`, `max: 128`) already run in
  `Flux.Accounts.User.validate_password/2`, so this stub strengthens nothing:
  `validate/2` returns the changeset unchanged and `expired?/1` never expires a
  password. The Enterprise edition overlays the real provider.
  """

  @behaviour Flux.Accounts.PasswordPolicy.Provider

  @impl true
  def validate(changeset, _organization_id), do: changeset

  @impl true
  def expired?(_scope), do: false
end
