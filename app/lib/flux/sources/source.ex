defmodule Flux.Sources.Source do
  @moduledoc """
  Schema for source configurations.

  A source represents an inbound origin for pipeline data. Each source has a
  type (webhook, poll, kafka, mqtt, sqs, kinesis) and a configuration map
  specific to that type.
  Sources land events onto the internal queue named by
  `Flux.Source.queue_name/2`; a pipeline consumes that queue to be fed.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Flux.Structure.Organization

  @source_types ~w(webhook poll kafka mqtt sqs kinesis)

  schema "sources" do
    field :name, :string
    field :description, :string
    field :type, :string
    field :config, :map, default: %{}
    field :enabled, :boolean, default: true

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(source, attrs) do
    source
    |> cast(attrs, [:name, :description, :type, :config, :enabled, :organization_id])
    |> validate_required([:name, :type, :organization_id])
    |> validate_inclusion(:type, @source_types)
    |> validate_config()
    # Attach the org-scoped name uniqueness error to :name (not :organization_id,
    # which reads as the confusing "Organization has already been taken").
    |> unique_constraint(:name,
      name: :sources_organization_id_name_index,
      message: "is already used by another source"
    )
    |> foreign_key_constraint(:organization_id)
  end

  defp validate_config(changeset) do
    type = get_field(changeset, :type)
    config = get_field(changeset, :config) || %{}

    case validate_config_for_type(type, config) do
      :ok ->
        changeset

      {:error, reasons} ->
        Enum.reduce(reasons, changeset, fn reason, cs ->
          add_error(cs, :config, reason)
        end)
    end
  end

  defp validate_config_for_type(nil, _config), do: :ok

  defp validate_config_for_type(type, config) do
    # Merge the type in so adapters keying on "type" (e.g. the Pro stub) resolve
    # the right gating feature.
    Flux.Source.validate_config(type, Map.put(config, "type", type))
  end
end
