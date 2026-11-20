defmodule Flux.Pipelines.Pipeline do
  @moduledoc """
  Ecto schema for a data pipeline.

  A pipeline belongs to an organization and is defined by its source/destination
  queues, an ordered map of processing `steps`, and the `sink_ids` it fans out
  to. `status` tracks its lifecycle (one of #{inspect(~w(active paused stopped))})
  and defaults to `"stopped"` so a newly created pipeline never runs until
  explicitly started.
  """
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
    # Source credentials in `nodes[].sourceConfig` (see `Flux.Pipelines.StepSecrets`)
    # are encrypted at rest; the rest of the steps IR is plain JSONB.
    field :steps, Flux.Vault.EncryptedConfig, secrets: Flux.Pipelines.StepSecrets, default: %{}
    field :sink_ids, {:array, :integer}, default: []

    # Set programmatically by Flux.Pipelines (never via changeset cast):
    # `current_version` tracks the live config's version; `running_version`
    # is the version the live Broadway runner loaded (nil when stopped).
    field :current_version, :integer
    field :running_version, :integer

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(pipeline, attrs) do
    pipeline
    |> cast(attrs, castable_fields(pipeline))
    |> validate_required([:name, :source_queue, :organization_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_steps()
    |> validate_sinks_in_organization()
    # Attach the org-scoped name uniqueness error to :name (not :organization_id,
    # which is the default for a field-list constraint and reads as the confusing
    # "Organization has already been taken").
    |> unique_constraint(:name,
      name: :pipelines_organization_id_name_index,
      message: "is already used by another pipeline"
    )
    |> foreign_key_constraint(:organization_id)
  end

  @fields ~w(name description source_queue destination_queue status config steps sink_ids)a

  # A pipeline's organization is set once, when it is created. Every create
  # caller fills it in on the server (from the caller's scope or the API key's
  # organization), and no update may move a pipeline to another organization.
  defp castable_fields(%__MODULE__{id: nil}), do: [:organization_id | @fields]
  defp castable_fields(%__MODULE__{}), do: @fields

  # The runner delivers to a pipeline's sinks with their stored, decrypted
  # credentials, so a pipeline may only reference its own organization's sinks.
  # Checked here because sink_ids reaches the changeset from several paths: the
  # API, the builder, import, and rollback to an older version.
  defp validate_sinks_in_organization(changeset) do
    case get_change(changeset, :sink_ids) do
      ids when is_list(ids) and ids != [] ->
        org_id = get_field(changeset, :organization_id)
        owned = Flux.Sinks.owned_sink_ids(ids, org_id)

        if Enum.all?(ids, &MapSet.member?(owned, &1)),
          do: changeset,
          else:
            add_error(
              changeset,
              :sink_ids,
              "references a sink that doesn't exist in this organization"
            )

      _ ->
        changeset
    end
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
