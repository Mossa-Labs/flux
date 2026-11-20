defmodule Flux.Repo.Migrations.CreateSinkDataSchema do
  use Ecto.Migration

  # Internal-mode Postgres sinks write only into this schema (see
  # Flux.Sink.Adapters.Postgres).
  #
  # Postgres checks the database-level CREATE privilege before it looks at
  # `IF NOT EXISTS`, so `CREATE SCHEMA IF NOT EXISTS` fails for a restricted app
  # role even when an administrator has already created the schema, as the
  # upgrade notes allow. Check for the schema first and only create it when it
  # is missing.
  def up do
    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'sink_data') THEN
        CREATE SCHEMA sink_data;
      END IF;
    END
    $$
    """)
  end

  # Without CASCADE, Postgres refuses to drop a schema that still holds tables,
  # so a rollback never deletes sink data.
  def down, do: execute("DROP SCHEMA IF EXISTS sink_data")
end
