defmodule Flux.Sinks do
  @moduledoc """
  The Sinks context manages sink configurations.

  Sinks are output destinations for pipeline data. This context provides
  CRUD operations for managing sink configurations.
  """

  import Ecto.Query, warn: false
  alias Flux.Repo
  alias Flux.Sinks.Sink

  @redacted "[REDACTED]"
  # Secret config paths masked before a sink leaves the system (e.g. API GETs).
  @secret_top_keys ~w(password private_key private_key_passphrase secret_access_key
                      credentials database_url sasl_password ssl_keyfile)
  @secret_auth_keys ~w(token password username key)

  @doc """
  Returns a copy of a sink's `config` with known secret fields masked.

  Covers HTTP auth (`auth.token|password|username|key`), Postgres/MySQL
  (`password`, `database_url`), S3 (`secret_access_key`), BigQuery
  (`credentials`), Kafka (`sasl_password`, `ssl_keyfile`), and Snowflake
  key-pair material (`private_key`, `private_key_passphrase`). Safe to call on
  any sink config map.
  """
  def redact_config(config) when is_map(config) do
    config
    |> redact_keys(@secret_top_keys)
    |> redact_auth()
  end

  def redact_config(other), do: other

  defp redact_keys(map, keys) do
    Enum.reduce(keys, map, fn key, acc ->
      if Map.has_key?(acc, key), do: Map.put(acc, key, @redacted), else: acc
    end)
  end

  defp redact_auth(%{"auth" => auth} = config) when is_map(auth) do
    Map.put(config, "auth", redact_keys(auth, @secret_auth_keys))
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
  end

  @doc """
  Updates a sink.

  ## Examples

      iex> update_sink(sink, %{field: new_value})
      {:ok, %Sink{}}

      iex> update_sink(sink, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_sink(%Sink{} = sink, attrs) do
    sink
    |> Sink.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Toggles the enabled status of a sink.
  """
  def toggle_enabled(%Sink{} = sink) do
    update_sink(sink, %{enabled: !sink.enabled})
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
    Repo.delete(sink)
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
