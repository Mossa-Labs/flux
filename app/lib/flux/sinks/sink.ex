defmodule Flux.Sinks.Sink do
  @moduledoc """
  Schema for sink configurations.

  A sink represents an output destination for pipeline data. Each sink
  has a type (http, s3, postgres, mysql) and a configuration map specific to
  that type.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Flux.Structure.Organization

  @sink_types ~w(http s3 postgres mysql)

  schema "sinks" do
    field :name, :string
    field :description, :string
    field :type, :string
    field :config, :map, default: %{}
    field :enabled, :boolean, default: true

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(sink, attrs) do
    sink
    |> cast(attrs, [:name, :description, :type, :config, :enabled, :organization_id])
    |> validate_required([:name, :type, :organization_id])
    |> validate_inclusion(:type, @sink_types)
    |> validate_config()
    |> unique_constraint([:organization_id, :name])
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
    case Flux.Sink.adapter_for_type(type) do
      {:ok, adapter} -> adapter.validate_config(config)
      {:error, _} -> {:error, ["unknown sink type"]}
    end
  end
end
