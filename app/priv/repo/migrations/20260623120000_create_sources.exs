defmodule Flux.Repo.Migrations.CreateSources do
  use Ecto.Migration

  def change do
    create table(:sources) do
      add :name, :string, null: false
      add :description, :text
      add :type, :string, null: false
      add :config, :map, default: %{}, null: false
      add :enabled, :boolean, default: true, null: false
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:sources, [:organization_id])
    create index(:sources, [:type])
    create unique_index(:sources, [:organization_id, :name])
  end
end
