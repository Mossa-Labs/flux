defmodule Flux.PipelinesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Flux.Pipelines` context.
  """

  @doc """
  Generate a pipeline.
  """
  def pipeline_fixture(organization_id, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "test-pipeline-#{System.unique_integer([:positive])}",
        source_queue: "test.queue.#{System.unique_integer([:positive])}",
        status: "stopped",
        config: %{},
        steps: %{"version" => "1.0", "steps" => []},
        sink_ids: [],
        organization_id: organization_id
      })

    {:ok, pipeline} = Flux.Pipelines.create_pipeline(attrs)
    pipeline
  end
end
