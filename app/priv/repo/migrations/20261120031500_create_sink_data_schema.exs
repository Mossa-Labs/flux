defmodule Flux.Repo.Migrations.CreateSinkDataSchema do
  use Ecto.Migration

  # Internal-mode Postgres sinks write only into this schema (see
  # Flux.Sink.Adapters.Postgres). Rolling back drops it only while it is empty:
  # without CASCADE, Postgres refuses to drop a schema that still holds tables,
  # so sink data is never deleted by a rollback.
  def up, do: execute("CREATE SCHEMA IF NOT EXISTS sink_data")
  def down, do: execute("DROP SCHEMA IF EXISTS sink_data")
end
