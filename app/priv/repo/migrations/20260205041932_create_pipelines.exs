defmodule Flux.Repo.Migrations.CreatePipelines do
  use Ecto.Migration

  def change do
    create table(:pipelines) do
      add :name, :string, null: false
      add :description, :text
      add :source_queue, :string, null: false
      add :destination_queue, :string
      add :status, :string, null: false, default: "stopped"
      add :config, :map, default: %{}
      add :steps, :map, default: %{}
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:pipelines, [:organization_id])
    create index(:pipelines, [:status])
    create unique_index(:pipelines, [:organization_id, :name])
  end
end
