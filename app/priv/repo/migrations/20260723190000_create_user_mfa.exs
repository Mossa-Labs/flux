defmodule Flux.Repo.Migrations.CreateUserMfa do
  use Ecto.Migration

  def change do
    create table(:user_mfa) do
      # TOTP secret and single-use backup codes, both encrypted at rest via
      # Flux.Vault with the row's user_id bound in as AAD (MOS-591 / MOS-484).
      add :secret, :map, null: false
      add :backup_codes, :map, null: false, default: %{}
      add :enabled_at, :utc_datetime

      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    # One MFA record per user.
    create unique_index(:user_mfa, [:user_id])
  end
end
