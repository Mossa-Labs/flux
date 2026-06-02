defmodule Flux.Repo.Migrations.CreateOrganizationMembers do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:organization_members) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :id, on_delete: :delete_all), null: false
      add :role, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists unique_index(:organization_members, [:organization_id, :user_id])
    create_if_not_exists index(:organization_members, [:user_id])
  end
end
