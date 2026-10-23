defmodule Flux.Repo.Migrations.UpgradeObanToV14 do
  use Ecto.Migration

  # Oban 2.24 refuses to start below migration version 14.
  #   v13: indexes on oban_jobs (state, cancelled_at) and (state, discarded_at)
  #   v14: adds the 'suspended' value to the oban_job_state enum
  def up do
    Oban.Migration.up(version: 14)
  end

  # Rolls back through v13, leaving the schema at v12. Postgres cannot drop an
  # enum value, so 'suspended' stays in the type; v14's down moves any suspended
  # jobs back to 'scheduled'.
  def down do
    Oban.Migration.down(version: 13)
  end
end
