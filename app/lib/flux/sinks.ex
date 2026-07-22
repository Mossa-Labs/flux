defmodule Flux.Sinks do
  @moduledoc """
  The Sinks context manages sink configurations.

  Sinks are output destinations for pipeline data. This context provides
  CRUD operations for managing sink configurations.
  """

  import Ecto.Query, warn: false
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
    |> scrub_wrappers()
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

  # Defense-in-depth: mask any encrypted wrapper that survives to the output —
  # e.g. a ciphertext blob a caller planted in a non-secret field, which is not
  # decrypted (see `Flux.Vault.decrypt_map/2`) and so would otherwise echo back.
  defp scrub_wrappers(%{"encrypted" => true}), do: @redacted

  defp scrub_wrappers(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {k, scrub_wrappers(v)} end)

  defp scrub_wrappers(list) when is_list(list), do: Enum.map(list, &scrub_wrappers/1)
  defp scrub_wrappers(value), do: value

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
  end

  @doc """
  Returns the list of enabled sinks for an organization.
  """
  def list_enabled_sinks(organization_id) do
    Sink
    |> where([s], s.organization_id == ^organization_id and s.enabled == true)
    |> order_by([s], asc: s.name)
    |> Repo.all()
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
  def get_sink!(id), do: Repo.get!(Sink, id)

  @doc """
  Gets a single sink by id and organization.

  Returns nil if not found.
  """
  def get_sink(id, organization_id) do
    Sink
    |> where([s], s.id == ^id and s.organization_id == ^organization_id)
    |> Repo.one()
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
