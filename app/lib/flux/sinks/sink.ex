defmodule Flux.Sinks.Sink do
  @moduledoc """
  Schema for sink configurations.

  A sink represents an output destination for pipeline data. Each sink
  has a type (http, s3, postgres, mysql, parquet, email, bigquery, kafka,
  snowflake, redis, mongodb, slack, dynamodb, gcs, cassandra, pagerduty) and a configuration
  map specific to that type.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Flux.Structure.Organization

  @sink_types ~w(http s3 postgres mysql parquet email bigquery kafka snowflake redis mongodb slack dynamodb gcs cassandra pagerduty)

  schema "sinks" do
    field :name, :string
    field :description, :string
    field :type, :string
    # Secret values within `config` are encrypted at rest by the custom type;
    # non-secret keys are stored as plain JSONB. Transparent on read/write.
    field :config, Flux.Vault.EncryptedConfig, secrets: Flux.Sinks.Secrets, default: %{}
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
    # Attach the org-scoped name uniqueness error to :name (not :organization_id,
    # which reads as the confusing "Organization has already been taken").
    |> unique_constraint(:name,
      name: :sinks_organization_id_name_index,
      message: "is already used by another sink"
    )
    |> foreign_key_constraint(:organization_id)
  end

  defp validate_config(changeset) do
    if unchanged_config_with_undecryptable_secrets?(changeset),
      do: changeset,
      else: do_validate_config(changeset)
  end

  # A stored secret that couldn't be decrypted loads as a marker (see
  # `Flux.Vault.decrypt_map/2`), which no adapter accepts as a secret. When the
  # update doesn't touch `config` (for example, disabling the broken sink),
  # skip re-validating it, so the sink can still be disabled or renamed. Any
  # change to `config` is validated as usual, so the secret has to be
  # re-entered before it saves.
  defp unchanged_config_with_undecryptable_secrets?(changeset) do
    config = changeset.data.config

    changeset.data.__meta__.state == :loaded and
      not Map.has_key?(changeset.changes, :config) and
      is_map(config) and
      Flux.Vault.undecryptable_paths(config, Flux.Sinks.Secrets.paths(config)) != []
  end

  defp do_validate_config(changeset) do
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
      # The type travels with the config (as it does at delivery time) so the
      # Community stub can name the type and the edition that entitles it.
      {:ok, adapter} -> adapter.validate_config(Map.put(config, "type", type))
      {:error, _} -> {:error, ["unknown sink type"]}
    end
  end
end
