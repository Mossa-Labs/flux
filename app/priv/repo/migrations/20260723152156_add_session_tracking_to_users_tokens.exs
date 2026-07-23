defmodule Flux.Repo.Migrations.AddSessionTrackingToUsersTokens do
  use Ecto.Migration

  def change do
    alter table(:users_tokens) do
      add :user_agent, :string
      add :ip_address, :string
      add :last_active_at, :utc_datetime
    end
  end
end
