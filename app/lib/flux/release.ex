defmodule Flux.Release do
  @moduledoc """
  Release tasks for the `flux` release, which has no Mix available.

  Run from the built release:

      bin/flux eval "Flux.Release.migrate()"

  Intended as a one-shot step before the app starts — an init container, a
  `docker compose run` job, or a manual deploy step. It does **not** create the
  database; provision that first.
  """
  require Logger

  @app :flux
  @repo Flux.Repo

  @doc """
  Runs every pending migration for `Flux.Repo`.
  """
  def migrate do
    load_app()
    path = migrations_path()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(@repo, fn repo ->
        Logger.info("[Flux.Release] migrating #{inspect(repo)} from #{path}")
        Ecto.Migrator.run(repo, path, :up, all: true)
      end)

    :ok
  end

  @doc """
  Rolls `Flux.Repo` back to `version`.

  Migrations are otherwise forward-only in deployment: prefer a corrective
  migration over rolling back a version that has already run in production.
  """
  def rollback(version) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(
        @repo,
        &Ecto.Migrator.run(&1, migrations_path(), :down, to: version)
      )

    :ok
  end

  @doc """
  Lists pipelines, and pipeline versions, whose queue names can't be placed
  inside their organization.

  Every queue name is a logical name that the server places inside the
  pipeline's organization (see `Flux.Queue.Naming`). A name written before
  that check existed may start with a reserved prefix (`org.`, `amq.`,
  `flux.`), or contain characters a broker can't use. A pipeline with such a
  `source_queue`, `destination_queue` or queue-type source node won't start,
  and rolling back to such a version is refused. Run this before upgrading and
  give each listed pipeline a valid name:

      bin/flux eval "Flux.Release.audit_queue_names()"

  It only reports; it never rewrites a name, because the name links a pipeline
  to whatever publishes into it. Returns the findings and logs one line each.
  """
  def audit_queue_names do
    load_app()

    {:ok, findings, _} = Ecto.Migrator.with_repo(@repo, &queue_name_findings/1)

    Enum.each(findings, fn finding ->
      Logger.warning(
        "[Flux.Release] #{finding.table} #{finding.id} (pipeline #{finding.pipeline_id}, " <>
          "organization #{finding.organization_id}): #{finding.field} " <>
          "#{inspect(finding.name)} #{Flux.Queue.Naming.error_message(finding.reason)}"
      )
    end)

    Logger.info("[Flux.Release] queue name audit: #{length(findings)} finding(s)")
    findings
  end

  @doc false
  # Raw rows, not schemas: this runs from `bin/flux eval` without the vault, and
  # queue names are never encrypted.
  def queue_name_findings(repo) do
    pipelines =
      repo.query!(
        "SELECT id, id, organization_id, source_queue, destination_queue, steps FROM pipelines ORDER BY id"
      )

    versions =
      repo.query!("""
      SELECT v.id, v.pipeline_id, p.organization_id, v.source_queue, v.destination_queue, v.steps
      FROM pipeline_versions v JOIN pipelines p ON p.id = v.pipeline_id
      ORDER BY v.id
      """)

    findings("pipelines", pipelines.rows) ++ findings("pipeline_versions", versions.rows)
  end

  defp findings(table, rows) do
    for [id, pipeline_id, org_id, source_queue, destination_queue, steps] <- rows,
        {field, name} <- [
          source_queue: source_queue,
          destination_queue: destination_queue,
          source_node_queue: Flux.Pipelines.Pipeline.source_node_queue(steps)
        ],
        name not in [nil, ""],
        {:error, reason} <- [Flux.Queue.Naming.validate_logical(name)] do
      %{
        table: table,
        id: id,
        pipeline_id: pipeline_id,
        organization_id: org_id,
        field: field,
        name: name,
        reason: reason
      }
    end
  end

  defp migrations_path, do: Application.app_dir(@app, "priv/repo/migrations")

  defp load_app, do: Application.load(@app)
end
