defmodule Flux.Pipelines.PipelineVersion do
  @moduledoc """
  An immutable snapshot of a pipeline's editable configuration at a point in time.

  Every config-changing save creates one version row representing the *resulting*
  saved state (not the prior state), so the latest version always mirrors the live
  pipeline config and `pipelines.current_version` points at it. Versions are
  insert-only — they are never updated, only pruned by retention.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Flux.Accounts.User
  alias Flux.Pipelines.Pipeline

  schema "pipeline_versions" do
    field :version, :integer
    field :name, :string
    field :source_queue, :string
    field :destination_queue, :string
    field :config, :map, default: %{}
    field :steps, :map, default: %{}
    field :sink_ids, {:array, :integer}, default: []
    field :change_summary, :string

    belongs_to :pipeline, Pipeline
    belongs_to :created_by_user, User, foreign_key: :created_by

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(version, attrs) do
    version
    |> cast(attrs, [
      :pipeline_id,
      :version,
      :name,
      :source_queue,
      :destination_queue,
      :config,
      :steps,
      :sink_ids,
      :created_by,
      :change_summary
    ])
    |> validate_required([:pipeline_id, :version])
    |> unique_constraint([:pipeline_id, :version])
    |> foreign_key_constraint(:pipeline_id)
    |> foreign_key_constraint(:created_by)
  end
end
