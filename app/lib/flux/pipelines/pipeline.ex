defmodule Flux.Pipelines.Pipeline do
  use Ecto.Schema
  import Ecto.Changeset

  alias Flux.Structure.Organization

  @statuses ~w(active paused stopped)

  schema "pipelines" do
    field :name, :string
    field :description, :string
    field :source_queue, :string
    field :destination_queue, :string
    field :status, :string, default: "stopped"
    field :config, :map, default: %{}
    field :steps, :map, default: %{}
    field :sink_ids, {:array, :integer}, default: []

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(pipeline, attrs) do
    pipeline
    |> cast(attrs, [
      :name,
      :description,
      :source_queue,
      :destination_queue,
      :status,
      :config,
      :steps,
      :sink_ids,
      :organization_id
    ])
    |> validate_required([:name, :source_queue, :organization_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_steps()
    |> unique_constraint([:organization_id, :name])
    |> foreign_key_constraint(:organization_id)
  end

  defp validate_steps(changeset) do
    case get_change(changeset, :steps) do
      nil ->
        changeset

      steps when is_map(steps) ->
        case validate_steps_format(steps) do
          :ok -> changeset
          {:error, reason} -> add_error(changeset, :steps, reason)
        end

      _ ->
        add_error(changeset, :steps, "must be a map")
    end
  end

  defp validate_steps_format(%{"version" => _, "steps" => steps}) when is_list(steps) do
    :ok
  end

  defp validate_steps_format(%{
         "version" => _,
         "steps" => steps,
         "nodes" => nodes,
         "edges" => edges
       })
       when is_list(steps) and is_list(nodes) and is_list(edges) do
    :ok
  end

  defp validate_steps_format(%{"version" => _, "steps" => steps, "nodes" => nodes})
       when is_list(steps) and is_list(nodes) do
    :ok
  end

  defp validate_steps_format(%{}) do
    :ok
  end

  defp validate_steps_format(_) do
    {:error, "must have version and steps keys"}
  end
end
