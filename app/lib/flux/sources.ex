defmodule Flux.Sources do
  @moduledoc """
  The Sources context manages source configurations.

  Sources are inbound origins for pipeline data (webhooks, scheduled polls,
  Kafka topics, ...). This context provides CRUD operations for managing source
  configurations, mirroring `Flux.Sinks`.
  """

  import Ecto.Query, warn: false
  alias Flux.Repo
  alias Flux.Sources.Secrets
  alias Flux.Sources.Source

  @redacted "[REDACTED]"

  @doc """
  Returns a copy of a source's `config` with known secret fields masked.

  Secret locations come from `Flux.Sources.Secrets`, the same taxonomy that
  drives encryption at rest, so every value decrypted on load is masked here.
  """
  def redact_config(config) when is_map(config) do
    config
    |> redact_keys(Secrets.top_keys())
    |> redact_auth()
    # Defense-in-depth: mask any ciphertext that survives to the output, e.g. a
    # wrapper planted in a non-secret field (never decrypted, see
    # `Flux.Vault.decrypt_map/2`).
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
  Returns the names of a source's secret keys that couldn't be decrypted with
  the current vault key, e.g. `["password"]` or `["auth.token"]`.

  An empty list means every stored secret decrypted (or there are none). See
  `Flux.Vault.decrypt_map/2` for how such secrets load.
  """
  @spec undecryptable_secrets(%Source{} | map()) :: [String.t()]
  def undecryptable_secrets(%Source{config: config}), do: undecryptable_secrets(config)

  def undecryptable_secrets(config) when is_map(config) do
    config
    |> Flux.Vault.undecryptable_paths(Secrets.paths(config))
    |> Enum.map(&Enum.join(&1, "."))
  end

  def undecryptable_secrets(_config), do: []

  @doc "Returns `true` if any of the source's stored secrets couldn't be decrypted."
  @spec undecryptable_secrets?(%Source{} | map()) :: boolean()
  def undecryptable_secrets?(source_or_config), do: undecryptable_secrets(source_or_config) != []

  @doc "Returns the list of sources for an organization."
  def list_sources(organization_id) do
    Source
    |> where([s], s.organization_id == ^organization_id)
    |> order_by([s], desc: s.updated_at)
    |> Repo.all()
  end

  @doc "Returns the list of enabled sources for an organization."
  def list_enabled_sources(organization_id) do
    Source
    |> where([s], s.organization_id == ^organization_id and s.enabled == true)
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  @doc """
  Returns every enabled source across all organizations.

  Used at boot to start active (long-lived) source ingestion processes.
  """
  def list_all_enabled_sources do
    Source
    |> where([s], s.enabled == true)
    |> Repo.all()
  end

  @doc "Gets sources by their IDs. Returns only sources that exist and are enabled."
  def get_sources_by_ids(ids) when is_list(ids) do
    Source
    |> where([s], s.id in ^ids and s.enabled == true)
    |> Repo.all()
  end

  @doc """
  Gets an organization's sources by name, regardless of `enabled` flag.

  Backs pipeline import (resolving `source_names` → ids), where a
  present-but-disabled source should still satisfy the reference.
  """
  def get_sources_by_names(names, organization_id) when is_list(names) do
    Source
    |> where([s], s.organization_id == ^organization_id and s.name in ^names)
    |> Repo.all()
  end

  @doc """
  Gets a single source.

  Raises `Ecto.NoResultsError` if the Source does not exist.
  """
  def get_source!(id), do: Repo.get!(Source, id)

  @doc "Gets a single source by id and organization. Returns nil if not found."
  def get_source(id, organization_id) do
    Source
    |> where([s], s.id == ^id and s.organization_id == ^organization_id)
    |> Repo.one()
  end

  @doc "Creates a source."
  def create_source(attrs \\ %{}) do
    %Source{}
    |> Source.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a source."
  def update_source(%Source{} = source, attrs) do
    source
    |> Source.changeset(attrs)
    |> Repo.update()
  end

  @doc "Toggles the enabled status of a source."
  def toggle_enabled(%Source{} = source) do
    update_source(source, %{enabled: !source.enabled})
  end

  @doc "Deletes a source."
  def delete_source(%Source{} = source) do
    Repo.delete(source)
  end

  @doc "Returns an `%Ecto.Changeset{}` for tracking source changes."
  def change_source(%Source{} = source, attrs \\ %{}) do
    Source.changeset(source, attrs)
  end

  @doc "Returns the count of sources for an organization."
  def count(organization_id) do
    Source
    |> where([s], s.organization_id == ^organization_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  The internal queue name a pipeline should consume to be fed by this source.
  """
  def queue_name(%Source{type: type, config: config}) do
    Flux.Source.queue_name(type, Map.put(config, "type", type))
  end

  @doc "Tests the connection for a source."
  def test_connection(%Source{type: type, config: config}) do
    Flux.Source.test_connection(type, Map.put(config, "type", type))
  end

  @doc """
  Starts the ingestion process for a source if it is active (no-op for passive
  sources). Returns the result of `Flux.Source.Supervisor.start_source/3`.
  """
  def start_ingestion(%Source{} = source) do
    config = Map.put(source.config, "type", source.type)
    opts = [source_id: source.id, organization_id: source.organization_id]
    Flux.Source.Supervisor.start_source(source.type, config, opts)
  end
end
