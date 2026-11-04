defmodule Flux.Sinks do
  @moduledoc """
  The Sinks context manages sink configurations.

  Sinks are output destinations for pipeline data. This context provides
  CRUD operations for managing sink configurations.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Flux.Repo
  alias Flux.Sinks.Sink

  alias Flux.Sinks.Secrets

  @redacted "[REDACTED]"

  @doc """
  Returns a copy of a sink's `config` with known secret fields masked.

  Covers HTTP auth (`auth.token|password|username|key`), Postgres/MySQL
  (`password`, `database_url`), S3 (`secret_access_key`), BigQuery
  (`credentials`), Kafka (`sasl_password`, `ssl_keyfile`), and Snowflake
  key-pair material (`private_key`, `private_key_passphrase`). Safe to call on
  any sink config map. Secret locations come from `Flux.Sinks.Secrets`.
  """
  def redact_config(config) when is_map(config) do
    config
    |> redact_keys(Secrets.top_keys())
    |> redact_auth()
    # Defense-in-depth: mask any encrypted wrapper that survives to the output —
    # e.g. a ciphertext blob a caller planted in a non-secret field, which is not
    # decrypted (see `Flux.Vault.decrypt_map/2`) and so would otherwise echo back.
    |> Flux.Vault.scrub_wrappers(@redacted)
  end

  def redact_config(other), do: other

  defp redact_keys(map, keys) do
    Enum.reduce(keys, map, fn key, acc ->
      if Map.has_key?(acc, key), do: Map.put(acc, key, @redacted), else: acc
    end)
  end

  defp redact_auth(%{"auth" => auth} = config) when is_map(auth) do
    Map.put(config, "auth", redact_keys(auth, Secrets.auth_keys()))
  end

  defp redact_auth(config), do: config

  @doc """
  Returns the list of sinks for an organization.

  ## Examples

      iex> list_sinks(organization_id)
      [%Sink{}, ...]

  """
  def list_sinks(organization_id) do
    Sink
    |> where([s], s.organization_id == ^organization_id)
    |> order_by([s], desc: s.updated_at)
    |> Repo.all()
    |> warn_undecryptable()
  end

  @doc """
  Returns the list of enabled sinks for an organization.
  """
  def list_enabled_sinks(organization_id) do
    Sink
    |> where([s], s.organization_id == ^organization_id and s.enabled == true)
    |> order_by([s], asc: s.name)
    |> Repo.all()
    |> warn_undecryptable()
  end

  @doc """
  Gets sinks by their IDs.

  Returns only sinks that exist and are enabled.
  """
  def get_sinks_by_ids(ids) when is_list(ids) do
    Sink
    |> where([s], s.id in ^ids and s.enabled == true)
    |> Repo.all()
  end

  @doc """
  Gets an organization's sinks by name.

  Unlike `get_sinks_by_ids/1`, this resolves a sink regardless of its `enabled`
  flag: it backs pipeline import (resolving `sink_names` → ids), where a
  present-but-disabled sink should still satisfy the reference — the imported
  pipeline starts stopped and the operator controls enabling.
  """
  def get_sinks_by_names(names, organization_id) when is_list(names) do
    Sink
    |> where([s], s.organization_id == ^organization_id and s.name in ^names)
    |> Repo.all()
  end

  @doc """
  Gets a single sink.

  Raises `Ecto.NoResultsError` if the Sink does not exist.

  ## Examples

      iex> get_sink!(123)
      %Sink{}

      iex> get_sink!(456)
      ** (Ecto.NoResultsError)

  """
  def get_sink!(id), do: Sink |> Repo.get!(id) |> warn_undecryptable()

  @doc """
  Returns the names of a sink's secret keys that couldn't be decrypted with the
  current vault key, e.g. `["routing_key"]` or `["auth.token"]`.

  An empty list means every stored secret decrypted (or there are none). See
  `Flux.Vault.decrypt_map/2` for how such secrets load.
  """
  @spec undecryptable_secrets(%Sink{} | map()) :: [String.t()]
  def undecryptable_secrets(%Sink{config: config}), do: undecryptable_secrets(config)

  def undecryptable_secrets(config) when is_map(config) do
    config
    |> Flux.Vault.undecryptable_paths(Secrets.paths(config))
    |> Enum.map(&Enum.join(&1, "."))
  end

  def undecryptable_secrets(_config), do: []

  @doc "Returns `true` if any of the sink's stored secrets couldn't be decrypted."
  @spec undecryptable_secrets?(%Sink{} | map()) :: boolean()
  def undecryptable_secrets?(sink_or_config), do: undecryptable_secrets(sink_or_config) != []

  # Logs one warning per affected sink so an operator can find the rows to fix.
  # Only key names and the sink id are logged, never ciphertext. Not called on
  # the delivery path (`get_sinks_by_ids/1`): there, each failed delivery is
  # already logged with the sink id and `:undecryptable_secret`.
  defp warn_undecryptable(sinks) when is_list(sinks) do
    Enum.each(sinks, &warn_undecryptable/1)
    sinks
  end

  defp warn_undecryptable(%Sink{} = sink) do
    case undecryptable_secrets(sink) do
      [] ->
        :ok

      keys ->
        Logger.warning(
          "Sink #{sink.id} has stored secrets that can't be decrypted with the current " <>
            "vault key (#{Enum.join(keys, ", ")}). Re-enter them on the sink's edit page."
        )
    end

    sink
  end

  defp warn_undecryptable(other), do: other

  @doc """
  Gets a single sink by id and organization.

  Returns nil if not found.
  """
  def get_sink(id, organization_id) do
    Sink
    |> where([s], s.id == ^id and s.organization_id == ^organization_id)
    |> Repo.one()
    |> warn_undecryptable()
  end

  @doc """
  Creates a sink.

  ## Examples

      iex> create_sink(%{field: value})
      {:ok, %Sink{}}

      iex> create_sink(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_sink(attrs \\ %{}) do
    %Sink{}
    |> Sink.changeset(attrs)
    |> Repo.insert()
    |> audit_sink(:sink_created, fn sink -> sink_snapshot(sink) end)
  end

  @doc """
  Updates a sink.

  ## Examples

      iex> update_sink(sink, %{field: new_value})
      {:ok, %Sink{}}

      iex> update_sink(sink, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_sink(%Sink{} = sink, attrs, opts \\ []) do
    changeset = Sink.changeset(sink, attrs)
    action = Keyword.get(opts, :audit_action, :sink_updated)
    # Redact `config` so secrets (auth tokens, credentials) never land in an
    # audit row — the diff records that config changed, not its values.
    changes = Flux.Audit.diff(changeset, redact: [:config])

    changeset
    |> Repo.update()
    |> audit_sink(action, fn _ -> changes end)
  end

  @doc """
  Toggles the enabled status of a sink.
  """
  def toggle_enabled(%Sink{} = sink) do
    action = if sink.enabled, do: :sink_disabled, else: :sink_enabled
    update_sink(sink, %{enabled: !sink.enabled}, audit_action: action)
  end

  @doc """
  Deletes a sink.

  ## Examples

      iex> delete_sink(sink)
      {:ok, %Sink{}}

      iex> delete_sink(sink)
      {:error, %Ecto.Changeset{}}

  """
  def delete_sink(%Sink{} = sink) do
    sink
    |> Repo.delete()
    |> audit_sink(:sink_deleted, fn deleted -> sink_snapshot(deleted) end)
  end

  # ── Audit helpers ────────────────────────────────────────────────
  defp audit_sink({:ok, %Sink{} = sink} = result, action, changes_fun) do
    Flux.Audit.log(%{
      organization_id: sink.organization_id,
      action: action,
      resource_type: :sink,
      resource_id: sink.id,
      changes: changes_fun.(sink)
    })

    result
  end

  defp audit_sink(result, _action, _changes_fun), do: result

  defp sink_snapshot(%Sink{} = sink) do
    %{"name" => sink.name, "type" => sink.type, "enabled" => sink.enabled}
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking sink changes.

  ## Examples

      iex> change_sink(sink)
      %Ecto.Changeset{data: %Sink{}}

  """
  def change_sink(%Sink{} = sink, attrs \\ %{}) do
    Sink.changeset(sink, attrs)
  end

  @doc """
  Returns the count of sinks for an organization.
  """
  def count(organization_id) do
    Sink
    |> where([s], s.organization_id == ^organization_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Tests the connection for a sink.

  Returns `:ok` if the connection is successful.
  """
  def test_connection(%Sink{type: type, config: config}) do
    Flux.Sink.test_connection(type, config)
  end
end
