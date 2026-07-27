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

  defp migrations_path, do: Application.app_dir(@app, "priv/repo/migrations")

  defp load_app, do: Application.load(@app)
end
