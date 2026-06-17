defmodule Flux.Repo.Migrations.CreatePipelineVersions do
  use Ecto.Migration

  def change do
    create table(:pipeline_versions) do
      add :pipeline_id, references(:pipelines, on_delete: :delete_all), null: false
      add :version, :integer, null: false
      add :name, :string
      add :source_queue, :string
      add :destination_queue, :string
      add :config, :map, default: %{}
      add :steps, :map, default: %{}
      add :sink_ids, {:array, :bigint}, default: []
      add :created_by, references(:users, on_delete: :nilify_all)
      add :change_summary, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:pipeline_versions, [:pipeline_id, :version])
    create index(:pipeline_versions, [:pipeline_id])

    alter table(:pipelines) do
      # Version number of the live config (the latest saved version).
      add :current_version, :integer
      # Version the live Broadway runner loaded; null when the pipeline is stopped.
      add :running_version, :integer
    end
  end
end
