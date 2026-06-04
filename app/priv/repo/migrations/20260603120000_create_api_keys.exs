defmodule Flux.Repo.Migrations.CreateApiKeys do
  use Ecto.Migration

  def change do
    create table(:api_keys) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      # Displayed prefix, e.g. "flux_pk_a1b2c3d4" — safe to show in UIs/logs.
      add :key_prefix, :string, null: false
      # SHA-256 hex of the full key. The plaintext key is never stored.
      add :key_hash, :string, null: false
      add :name, :string, null: false
      # Coarse role the key acts as for authorization (admin | member | viewer).
      add :role, :string, null: false, default: "admin"
      add :last_used_at, :utc_datetime
      add :expires_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:api_keys, [:key_hash])
    create index(:api_keys, [:organization_id])
  end
end
