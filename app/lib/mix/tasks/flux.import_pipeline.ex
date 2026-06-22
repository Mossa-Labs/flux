defmodule Mix.Tasks.Flux.ImportPipeline do
  @shortdoc "Imports a pipeline configuration from portable JSON"

  @moduledoc """
  Imports a pipeline from a portable JSON export (see
  `Flux.Pipelines.PortableConfig`) into an organization. Sink references are
  resolved by name within the target org; the imported pipeline is created
  stopped.

  ## Examples

      mix flux.import_pipeline webhook-processor.flux.json --org 1
      mix flux.import_pipeline webhook-processor.flux.json --org 1 --name "copy"

  ## Options

    * `--org`  — target organization id. May be omitted when exactly one
      organization exists.
    * `--name` — override the pipeline name (to import a renamed copy and avoid a
      name collision).
  """

  use Mix.Task

  import Ecto.Query, only: [from: 2]

  alias Flux.Pipelines.PortableConfig
  alias Flux.Repo
  alias Flux.Structure.Organization

  @switches [org: :integer, name: :string]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, rest, _} = OptionParser.parse(args, strict: @switches)

    file =
      case rest do
        [file | _] -> file
        [] -> Mix.raise("Usage: mix flux.import_pipeline <file.json> [--org id] [--name name]")
      end

    envelope =
      case file |> File.read!() |> Jason.decode() do
        {:ok, decoded} -> decoded
        {:error, %Jason.DecodeError{} = e} -> Mix.raise("Invalid JSON: #{Exception.message(e)}")
      end

    org_id = resolve_org(opts[:org])

    case PortableConfig.import_pipeline(envelope, org_id, name: opts[:name]) do
      {:ok, pipeline} ->
        Mix.shell().info("Imported pipeline ##{pipeline.id} \"#{pipeline.name}\" (stopped)")

      {:error, {:unsupported_version, version}} ->
        Mix.raise("Unsupported export version: #{version}")

      {:error, {reason, message}} when reason in [:invalid_format, :invalid_steps] ->
        Mix.raise(message)

      {:error, {:missing_sinks, names}} ->
        Mix.raise("Unknown sinks in organization #{org_id}: #{Enum.join(names, ", ")}")

      {:error, %Ecto.Changeset{} = changeset} ->
        Mix.raise(changeset_message(changeset))
    end
  end

  # The only unique constraint on pipelines is (organization_id, name); the error
  # attaches to :organization_id, so detect it by constraint for a clear message.
  defp changeset_message(changeset) do
    if Enum.any?(changeset.errors, fn {_field, {_msg, opts}} -> opts[:constraint] == :unique end) do
      "A pipeline with that name already exists in this organization (use --name to import a copy)"
    else
      "Import failed: #{format_changeset(changeset)}"
    end
  end

  defp resolve_org(nil) do
    case Repo.all(from(o in Organization, select: o.id)) do
      [id] -> id
      [] -> Mix.raise("No organizations exist; create one first")
      _ -> Mix.raise("Multiple organizations exist; pass --org <id>")
    end
  end

  defp resolve_org(id), do: id

  defp format_changeset(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, errs} -> "#{field} #{Enum.join(errs, ", ")}" end)
  end
end
