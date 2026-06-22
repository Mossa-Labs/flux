defmodule Flux.Pipelines.PortableConfig do
  @moduledoc """
  Export and import of pipeline configurations as portable JSON.

  The export envelope references sinks by **name**, never by id, and never
  includes sink `config` — so a config is portable across environments and
  carries no secrets (tokens/passwords live only in the sink config, which is
  excluded). Import resolves the names back to sink ids within the target
  organization, validates the steps IR, and always creates a **stopped**
  pipeline.

  Envelope shape (`@envelope_version`):

      %{
        "flux_export" => "1.0",
        "exported_at" => "<ISO8601 UTC>",
        "pipeline" => %{
          "name" => ..., "description" => ...,
          "source_queue" => ..., "destination_queue" => ...,
          "steps" => %{"version" => "1.0", "steps" => [...]},
          "config" => %{...},
          "sink_names" => ["http-slack", "postgres-events"]
        }
      }
  """

  alias Flux.Pipeline.StepRegistry
  alias Flux.Pipelines
  alias Flux.Pipelines.Pipeline
  alias Flux.Sinks

  @envelope_version "1.0"

  @pipeline_keys ~w(name description source_queue destination_queue steps config)

  @doc """
  Builds the portable export envelope for a pipeline (struct or id).

  Sink ids are resolved to names in their original order; a referenced sink that
  no longer exists is dropped (import re-resolves by name regardless).
  """
  @spec export_pipeline(%Pipeline{} | integer() | String.t()) :: map()
  def export_pipeline(%Pipeline{} = pipeline) do
    %{
      "flux_export" => @envelope_version,
      "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "pipeline" => %{
        "name" => pipeline.name,
        "description" => pipeline.description,
        "source_queue" => pipeline.source_queue,
        "destination_queue" => pipeline.destination_queue,
        "steps" => pipeline.steps,
        "config" => pipeline.config,
        "sink_names" => sink_names_for(pipeline)
      }
    }
  end

  def export_pipeline(id), do: id |> Pipelines.get_pipeline!() |> export_pipeline()

  @doc """
  Imports a pipeline from an export envelope into `organization_id`.

  Resolves `sink_names` → ids in the org, validates the steps IR, forces
  `status: "stopped"`, and creates the pipeline (recorded as version 1).
  `organization_id` is always taken from the caller — the envelope carries no
  ids or org, so an import can never reference another org's sinks.

  ## Options

    * `:name` — override the pipeline name (e.g. to import a renamed copy and
      avoid a name collision).
    * `:actor_id` — forwarded to `Flux.Pipelines.create_pipeline/2` for version
      authorship.
  """
  @spec import_pipeline(map(), integer(), keyword()) ::
          {:ok, %Pipeline{}}
          | {:error, {:unsupported_version, String.t()}}
          | {:error, {:invalid_format, String.t()}}
          | {:error, {:invalid_steps, String.t()}}
          | {:error, {:missing_sinks, [String.t()]}}
          | {:error, Ecto.Changeset.t()}
  def import_pipeline(envelope, organization_id, opts \\ []) do
    with {:ok, obj} <- validate_envelope(envelope),
         :ok <- validate_pipeline_keys(obj),
         :ok <- validate_steps_ir(Map.get(obj, "steps")),
         {:ok, sink_ids} <- resolve_sink_ids(Map.get(obj, "sink_names", []), organization_id) do
      obj
      |> Map.take(@pipeline_keys)
      |> Map.merge(%{
        "sink_ids" => sink_ids,
        "organization_id" => organization_id,
        "status" => "stopped"
      })
      |> maybe_override_name(opts)
      |> Pipelines.create_pipeline(opts)
    end
  end

  @doc "Suggested download filename for a pipeline export, e.g. `my-pipeline.flux.json`."
  @spec suggested_filename(%Pipeline{} | String.t()) :: String.t()
  def suggested_filename(%Pipeline{name: name}), do: suggested_filename(name)

  def suggested_filename(name) when is_binary(name) do
    slug =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    "#{if(slug == "", do: "pipeline", else: slug)}.flux.json"
  end

  # -- Private --

  defp sink_names_for(%Pipeline{sink_ids: ids, organization_id: org_id}) do
    names_by_id =
      org_id
      |> Sinks.list_sinks()
      |> Map.new(&{&1.id, &1.name})

    (ids || [])
    |> Enum.map(&names_by_id[&1])
    |> Enum.reject(&is_nil/1)
  end

  defp validate_envelope(%{"flux_export" => version, "pipeline" => obj}) when is_map(obj) do
    if version == @envelope_version,
      do: {:ok, obj},
      else: {:error, {:unsupported_version, to_string(version)}}
  end

  defp validate_envelope(%{"flux_export" => _}),
    do: {:error, {:invalid_format, ~s(missing or invalid "pipeline" object)}}

  defp validate_envelope(_), do: {:error, {:invalid_format, ~s(missing "flux_export" field)}}

  defp validate_pipeline_keys(obj) do
    cond do
      blank?(Map.get(obj, "name")) ->
        {:error, {:invalid_format, "pipeline.name is required"}}

      blank?(Map.get(obj, "source_queue")) ->
        {:error, {:invalid_format, "pipeline.source_queue is required"}}

      true ->
        :ok
    end
  end

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")

  # Native/ai steps resolve through the StepRegistry; script steps carry inline
  # code and have no registered operation, so skip them. Structural shape
  # (version/steps) is enforced later by Pipeline.changeset at create time.
  defp validate_steps_ir(%{"steps" => steps}) when is_list(steps) do
    unknown =
      steps
      |> Enum.flat_map(&registry_operation/1)
      |> Enum.reject(fn op -> match?({:ok, _}, StepRegistry.lookup(op)) end)
      |> Enum.uniq()

    case unknown do
      [] -> :ok
      ops -> {:error, {:invalid_steps, "unknown step operations: #{Enum.join(ops, ", ")}"}}
    end
  end

  defp validate_steps_ir(_), do: :ok

  defp registry_operation(%{"type" => "script"}), do: []
  defp registry_operation(%{"operation" => op}) when is_binary(op), do: [op]
  defp registry_operation(_), do: []

  defp resolve_sink_ids(names, _org_id) when names in [nil, []], do: {:ok, []}

  defp resolve_sink_ids(names, org_id) when is_list(names) do
    by_name =
      names
      |> Sinks.get_sinks_by_names(org_id)
      |> Map.new(&{&1.name, &1.id})

    case Enum.reject(names, &Map.has_key?(by_name, &1)) do
      [] -> {:ok, Enum.map(names, &by_name[&1])}
      missing -> {:error, {:missing_sinks, Enum.uniq(missing)}}
    end
  end

  defp resolve_sink_ids(_names, _org_id),
    do: {:error, {:invalid_format, "pipeline.sink_names must be a list"}}

  defp maybe_override_name(attrs, opts) do
    case Keyword.get(opts, :name) do
      nil -> attrs
      name -> Map.put(attrs, "name", name)
    end
  end
end
