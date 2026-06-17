defmodule Flux.Pipelines do
  @moduledoc """
  The Pipelines context manages pipeline configurations and lifecycle.

  ## Versioning

  Every save that changes a pipeline's editable configuration (`name`,
  `source_queue`, `destination_queue`, `config`, `steps`, `sink_ids`) records an
  immutable `PipelineVersion` snapshot of the *resulting* state and advances
  `pipeline.current_version` to point at it. Lifecycle-only changes (start/stop/
  pause via `update_status/2`) do not create versions. History is capped at 50
  versions per pipeline and pruned on save. Rollback is non-destructive:
  it re-applies an old snapshot as a new versioned save.
  """

  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias Flux.Repo
  alias Flux.Pipelines.{Pipeline, PipelineVersion}

  # Editable config fields whose change triggers a new version snapshot.
  @versioned_fields ~w(name source_queue destination_queue config steps sink_ids)a

  # Retention: keep at most this many versions per pipeline.
  @max_versions 50

  @doc """
  Returns the list of pipelines for an organization.

  ## Examples

      iex> list_pipelines(organization_id)
      [%Pipeline{}, ...]

  """
  def list_pipelines(organization_id) do
    Pipeline
    |> where([p], p.organization_id == ^organization_id)
    |> order_by([p], desc: p.updated_at)
    |> Repo.all()
  end

  @doc """
  Returns all active pipelines across all organizations.
  Used for auto-starting pipelines on application boot.
  """
  def list_active_pipelines do
    Pipeline
    |> where([p], p.status == "active")
    |> Repo.all()
  end

  @doc """
  Gets a single pipeline.

  Raises `Ecto.NoResultsError` if the Pipeline does not exist.

  ## Examples

      iex> get_pipeline!(123)
      %Pipeline{}

      iex> get_pipeline!(456)
      ** (Ecto.NoResultsError)

  """
  def get_pipeline!(id), do: Repo.get!(Pipeline, id)

  @doc """
  Gets a single pipeline by id and organization.

  Returns nil if not found.
  """
  def get_pipeline(id, organization_id) do
    Pipeline
    |> where([p], p.id == ^id and p.organization_id == ^organization_id)
    |> Repo.one()
  end

  @doc """
  Creates a pipeline, recording its initial configuration as version 1.

  ## Options

    * `:actor_id` — id of the user creating the pipeline, recorded as the
      version's `created_by`.

  ## Examples

      iex> create_pipeline(%{field: value})
      {:ok, %Pipeline{}}

      iex> create_pipeline(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_pipeline(attrs \\ %{}, opts \\ []) do
    changeset = Pipeline.changeset(%Pipeline{}, attrs)

    Multi.new()
    |> Multi.insert(:pipeline, changeset)
    |> Multi.run(:version, fn repo, %{pipeline: pipeline} ->
      insert_version(repo, pipeline, 1, "Created pipeline", opts[:actor_id])
    end)
    |> Multi.update(:pipeline_with_version, fn %{pipeline: pipeline} ->
      Ecto.Changeset.change(pipeline, current_version: 1)
    end)
    |> Repo.transaction()
    |> unwrap_versioned_result()
  end

  @doc """
  Updates a pipeline.

  When the change touches an editable config field, the resulting state is
  snapshotted as a new version (within the same transaction) and old versions are
  pruned. Lifecycle-only changes (e.g. `status`) update in place with no version.

  ## Options

    * `:actor_id` — id of the acting user, recorded as the version's `created_by`.
    * `:change_summary` — overrides the auto-generated change summary.

  ## Examples

      iex> update_pipeline(pipeline, %{field: new_value})
      {:ok, %Pipeline{}}

      iex> update_pipeline(pipeline, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_pipeline(%Pipeline{} = pipeline, attrs, opts \\ []) do
    changeset = Pipeline.changeset(pipeline, attrs)

    if versioned_change?(changeset) do
      versioned_update(pipeline, changeset, opts)
    else
      Repo.update(changeset)
    end
  end

  @doc """
  Updates the pipeline status.

  This is a lifecycle-only change and never creates a version snapshot.
  """
  def update_status(%Pipeline{} = pipeline, status) when status in ~w(active paused stopped) do
    update_pipeline(pipeline, %{status: status})
  end

  @doc """
  Sets the version the live runner loaded (or `nil` when stopped).

  Runtime state only — bypasses config versioning entirely.
  """
  def set_running_version(%Pipeline{} = pipeline, version) do
    pipeline
    |> Ecto.Changeset.change(running_version: version)
    |> Repo.update()
  end

  @doc """
  Lists a pipeline's versions, newest first, with the authoring user preloaded.
  """
  def list_pipeline_versions(pipeline_id) do
    PipelineVersion
    |> where([v], v.pipeline_id == ^pipeline_id)
    |> order_by([v], desc: v.version)
    |> preload(:created_by_user)
    |> Repo.all()
  end

  @doc """
  Gets a single pipeline version by pipeline id and version number.

  Returns nil if not found.
  """
  def get_pipeline_version(pipeline_id, version) do
    PipelineVersion
    |> where([v], v.pipeline_id == ^pipeline_id and v.version == ^version)
    |> preload(:created_by_user)
    |> Repo.one()
  end

  @doc """
  Rolls a pipeline back to a previous version.

  Non-destructive: loads the target snapshot and applies it as a new versioned
  save, creating a fresh version entry rather than mutating history.

  Returns `{:error, :version_not_found}` if the version does not exist.
  """
  def rollback_pipeline(%Pipeline{} = pipeline, version, opts \\ []) do
    case get_pipeline_version(pipeline.id, version) do
      nil ->
        {:error, :version_not_found}

      snapshot ->
        attrs = %{
          name: snapshot.name,
          source_queue: snapshot.source_queue,
          destination_queue: snapshot.destination_queue,
          config: snapshot.config,
          steps: snapshot.steps,
          sink_ids: snapshot.sink_ids || []
        }

        opts = Keyword.put_new(opts, :change_summary, "Rolled back to version #{version}")
        update_pipeline(pipeline, attrs, opts)
    end
  end

  @doc """
  Deletes a pipeline.

  ## Examples

      iex> delete_pipeline(pipeline)
      {:ok, %Pipeline{}}

      iex> delete_pipeline(pipeline)
      {:error, %Ecto.Changeset{}}

  """
  def delete_pipeline(%Pipeline{} = pipeline) do
    Repo.delete(pipeline)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking pipeline changes.

  ## Examples

      iex> change_pipeline(pipeline)
      %Ecto.Changeset{data: %Pipeline{}}

  """
  def change_pipeline(%Pipeline{} = pipeline, attrs \\ %{}) do
    Pipeline.changeset(pipeline, attrs)
  end

  # ── Versioning internals ─────────────────────────────────────────

  defp versioned_change?(changeset) do
    changeset.changes
    |> Map.take(@versioned_fields)
    |> map_size() > 0
  end

  defp versioned_update(pipeline, changeset, opts) do
    summary = opts[:change_summary] || summarize_changes(pipeline, changeset.changes)

    Multi.new()
    |> Multi.update(:pipeline, changeset)
    |> Multi.run(:version_number, fn repo, _ ->
      {:ok, next_version_number(repo, pipeline.id)}
    end)
    |> Multi.run(:version, fn repo, %{pipeline: updated, version_number: n} ->
      insert_version(repo, updated, n, summary, opts[:actor_id])
    end)
    |> Multi.update(:pipeline_with_version, fn %{pipeline: updated, version_number: n} ->
      Ecto.Changeset.change(updated, current_version: n)
    end)
    |> Multi.run(:prune, fn repo, %{version_number: n} ->
      prune_versions(repo, pipeline.id, n)
      {:ok, :pruned}
    end)
    |> Repo.transaction()
    |> unwrap_versioned_result()
  end

  defp unwrap_versioned_result({:ok, %{pipeline_with_version: pipeline}}), do: {:ok, pipeline}
  defp unwrap_versioned_result({:error, :pipeline, %Ecto.Changeset{} = cs, _}), do: {:error, cs}
  defp unwrap_versioned_result({:error, _step, reason, _}), do: {:error, reason}

  defp insert_version(repo, pipeline, version_number, summary, actor_id) do
    %PipelineVersion{}
    |> PipelineVersion.changeset(%{
      pipeline_id: pipeline.id,
      version: version_number,
      name: pipeline.name,
      source_queue: pipeline.source_queue,
      destination_queue: pipeline.destination_queue,
      config: pipeline.config,
      steps: pipeline.steps,
      sink_ids: pipeline.sink_ids || [],
      created_by: actor_id,
      change_summary: summary
    })
    |> repo.insert()
  end

  defp next_version_number(repo, pipeline_id) do
    max =
      PipelineVersion
      |> where([v], v.pipeline_id == ^pipeline_id)
      |> select([v], max(v.version))
      |> repo.one()

    (max || 0) + 1
  end

  defp prune_versions(repo, pipeline_id, latest_version) do
    threshold = latest_version - @max_versions

    if threshold > 0 do
      PipelineVersion
      |> where([v], v.pipeline_id == ^pipeline_id and v.version <= ^threshold)
      |> repo.delete_all()
    end
  end

  # Best-effort human-readable summary of what changed, for the version list.
  defp summarize_changes(old_pipeline, changes) do
    parts =
      [
        step_change_summary(old_pipeline.steps, Map.get(changes, :steps)),
        if(Map.has_key?(changes, :sink_ids), do: "Changed sink configuration"),
        if(Map.has_key?(changes, :name), do: "Renamed pipeline"),
        if(Map.has_key?(changes, :destination_queue), do: "Changed destination queue"),
        if(Map.has_key?(changes, :source_queue), do: "Changed source queue"),
        if(Map.has_key?(changes, :config), do: "Updated settings")
      ]
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> "Updated pipeline configuration"
      parts -> Enum.join(parts, ", ")
    end
  end

  defp step_change_summary(_old_steps, nil), do: nil

  defp step_change_summary(old_steps, new_steps) do
    old_list = steps_list(old_steps)
    new_list = steps_list(new_steps)

    cond do
      length(new_list) > length(old_list) -> added_step_summary(old_list, new_list)
      length(new_list) < length(old_list) -> "Removed a step"
      new_list != old_list -> "Modified pipeline steps"
      true -> nil
    end
  end

  defp added_step_summary(old_list, new_list) do
    case new_list -- old_list do
      [step | _] -> "Added #{step_label(step)} step"
      [] -> "Added a step"
    end
  end

  defp step_label(%{"operation" => op}) when is_binary(op) and op != "", do: op
  defp step_label(%{"type" => type}) when is_binary(type) and type != "", do: type
  defp step_label(_), do: "a"

  defp steps_list(%{"steps" => steps}) when is_list(steps), do: steps
  defp steps_list(_), do: []
end
