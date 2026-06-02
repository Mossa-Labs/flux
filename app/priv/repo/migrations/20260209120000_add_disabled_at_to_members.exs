defmodule Flux.Repo.Migrations.AddDisabledAtToMembers do
  use Ecto.Migration

  def change do
    alter table(:team_members) do
      add :disabled_at, :utc_datetime
    end

    alter table(:organization_members) do
      add :disabled_at, :utc_datetime
    end
  end
end
