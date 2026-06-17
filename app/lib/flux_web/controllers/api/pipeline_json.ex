defmodule FluxWeb.API.PipelineJSON do
  @moduledoc "JSON rendering for the pipelines API (explicit field whitelist)."

  @doc "Renders a list of pipelines (summary view)."
  def index(%{pipelines: pipelines}) do
    %{data: Enum.map(pipelines, &summary/1)}
  end

  @doc "Renders a single pipeline with full config + metrics."
  def show(%{pipeline: pipeline, metrics: metrics}) do
    %{data: detail(pipeline, metrics)}
  end

  @doc "Renders a pipeline's id + status (start/stop responses)."
  def status(%{pipeline: pipeline}) do
    %{data: %{id: pipeline.id, status: pipeline.status}}
  end

  defp summary(p) do
    %{
      id: p.id,
      name: p.name,
      status: p.status,
      source_queue: p.source_queue,
      sink_count: length(p.sink_ids || []),
      updated_at: p.updated_at
    }
  end

  defp detail(p, metrics) do
    %{
      id: p.id,
      name: p.name,
      description: p.description,
      status: p.status,
      source_queue: p.source_queue,
      destination_queue: p.destination_queue,
      config: p.config,
      steps: p.steps,
      sink_ids: p.sink_ids || [],
      current_version: p.current_version,
      running_version: p.running_version,
      metrics: metrics,
      inserted_at: p.inserted_at,
      updated_at: p.updated_at
    }
  end
end
