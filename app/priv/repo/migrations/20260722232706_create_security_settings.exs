defmodule Flux.Repo.Migrations.CreateSecuritySettings do
  use Ecto.Migration

  def change do
    create table(:security_settings) do
      add :ip_allowlist, {:array, :string}, null: false, default: []

      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    # One settings row per organization.
    create unique_index(:security_settings, [:organization_id])
  end
end
