defmodule Flux.Repo.Migrations.CreateSinks do
  use Ecto.Migration

  def change do
    create table(:sinks) do
      add :name, :string, null: false
      add :description, :text
      add :type, :string, null: false
      add :config, :map, default: %{}, null: false
      add :enabled, :boolean, default: true, null: false
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:sinks, [:organization_id])
    create index(:sinks, [:type])
    create unique_index(:sinks, [:organization_id, :name])

    alter table(:pipelines) do
      add :sink_ids, {:array, :bigint}, default: []
    end
  end
end
