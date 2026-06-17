defmodule FluxWeb.API.PipelineVersionJSON do
  @moduledoc "JSON rendering for the pipeline versions API (explicit field whitelist)."

  alias FluxWeb.API.PipelineJSON

  @doc "Renders a list of pipeline versions, newest first."
  def index(%{versions: versions}) do
    %{data: Enum.map(versions, &version/1)}
  end

  @doc "Renders the (rolled-back) pipeline detail, reusing the pipeline view."
  def pipeline(%{pipeline: pipeline}) do
    PipelineJSON.show(%{pipeline: pipeline, metrics: nil})
  end

  defp version(v) do
    %{
      id: v.id,
      version: v.version,
      change_summary: v.change_summary,
      created_by: v.created_by,
      inserted_at: v.inserted_at
    }
  end
end
