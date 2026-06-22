defmodule Mix.Tasks.Flux.ExportPipeline do
  @shortdoc "Exports a pipeline configuration to portable JSON"

  @moduledoc """
  Exports a pipeline's configuration as a portable JSON envelope (sink names, no
  secrets — see `Flux.Pipelines.PortableConfig`).

  ## Examples

      # Print to stdout (pipeable)
      mix flux.export_pipeline 1

      # Write to a file
      mix flux.export_pipeline 1 --out webhook-processor.flux.json
  """

  use Mix.Task

  alias Flux.Pipelines.PortableConfig

  @switches [out: :string]
  @aliases [o: :out]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, rest, _} = OptionParser.parse(args, strict: @switches, aliases: @aliases)

    id =
      case rest do
        [id | _] -> id
        [] -> Mix.raise("Usage: mix flux.export_pipeline <id> [--out file.json]")
      end

    json =
      try do
        id |> PortableConfig.export_pipeline() |> Jason.encode!(pretty: true)
      rescue
        Ecto.NoResultsError -> Mix.raise("Pipeline ##{id} not found")
      end

    case opts[:out] do
      nil ->
        IO.puts(json)

      path ->
        File.write!(path, json)
        Mix.shell().info("Exported pipeline ##{id} to #{path}")
    end
  end
end
