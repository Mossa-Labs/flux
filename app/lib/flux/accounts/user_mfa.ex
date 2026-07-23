defmodule Flux.Accounts.UserMfa do
  @moduledoc """
  Ecto schema for a user's TOTP multi-factor authentication (MOS-591).

  Both `secret` (the TOTP shared secret) and `backup_codes` (10 single-use recovery
  codes) are stored as `Flux.Vault` AAD-bound wrapper maps — encrypted at rest and
  cryptographically bound to the owning `user_id`, so a ciphertext lifted from one row
  cannot be decrypted against another. Encryption/decryption lives in
  `Flux.Accounts.Mfa`; this module only persists the already-wrapped values.

  `enabled_at` is `nil` while enrollment is pending (secret generated but the first
  code not yet confirmed) and stamped once the user verifies a code.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_mfa" do
    field :secret, :map, redact: true
    field :backup_codes, :map, redact: true
    field :enabled_at, :utc_datetime

    belongs_to :user, Flux.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating/updating an MFA record.

  `user_id` is set programmatically (via the owning struct) and is deliberately not
  cast. `secret` and `backup_codes` must already be encrypted wrapper maps.
  """
  def changeset(user_mfa, attrs) do
    user_mfa
    |> cast(attrs, [:secret, :backup_codes, :enabled_at])
    |> validate_required([:secret, :backup_codes])
    |> unique_constraint(:user_id)
  end
end
