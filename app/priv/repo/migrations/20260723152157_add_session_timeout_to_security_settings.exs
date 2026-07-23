defmodule Flux.Repo.Migrations.AddSessionTimeoutToSecuritySettings do
  use Ecto.Migration

  def change do
    alter table(:security_settings) do
      # Idle session timeout in minutes. Default 30 days; minimum 1 hour.
      add :session_timeout_minutes, :integer, null: false, default: 43_200
    end
  end
end
