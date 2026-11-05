defmodule Flux.Sources.Source do
  @moduledoc """
  Schema for source configurations.

  A source represents an inbound origin for pipeline data. Each source has a
  type (webhook, poll, kafka, mqtt, sqs, kinesis, pubsub, rabbitmq_external,
  sftp, grpc) and a configuration map specific to that type.
  Sources land events onto the internal queue named by
  `Flux.Source.queue_name/2`; a pipeline consumes that queue to be fed.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Flux.Structure.Organization

  @source_types ~w(webhook poll kafka mqtt sqs kinesis pubsub rabbitmq_external sftp grpc)

  schema "sources" do
    field :name, :string
    field :description, :string
    field :type, :string
    # Secret values within `config` (see `Flux.Sources.Secrets`) are encrypted at
    # rest by the custom type; everything else is plain JSONB. Callers and
    # adapters always see plaintext.
    field :config, Flux.Vault.EncryptedConfig, secrets: Flux.Sources.Secrets, default: %{}
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

  # A stored secret that couldn't be decrypted loads as a marker (see
  # `Flux.Vault.decrypt_map/2`), which no adapter accepts as a secret, so the
  # adapter never validates a config that holds one:
  #
  #   * When the update touches neither `config` nor `type` (for example,
  #     disabling the broken source), skip validation, so the source can still
  #     be disabled or renamed. The original ciphertext is stored back as is.
  #   * Otherwise, say which secret has to be re-entered, instead of letting
  #     the adapter report it as missing.
  defp validate_config(changeset) do
    config = get_field(changeset, :config) || %{}

    case Flux.Sources.undecryptable_secrets(config) do
      [] ->
        do_validate_config(changeset, config)

      keys ->
        if config_and_type_unchanged?(changeset),
          do: changeset,
          else: add_error(changeset, :config, undecryptable_message(keys))
    end
  end

  defp config_and_type_unchanged?(changeset) do
    changeset.data.__meta__.state == :loaded and
      not Map.has_key?(changeset.changes, :config) and
      not Map.has_key?(changeset.changes, :type)
  end

  defp undecryptable_message([key]),
    do: "#{key} can't be decrypted with the current vault key; re-enter it"

  defp undecryptable_message(keys),
    do: "#{Enum.join(keys, ", ")} can't be decrypted with the current vault key; re-enter them"

  defp do_validate_config(changeset, config) do
    type = get_field(changeset, :type)

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
