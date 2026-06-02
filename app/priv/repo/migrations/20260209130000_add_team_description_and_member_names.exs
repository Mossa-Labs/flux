defmodule Flux.Repo.Migrations.AddTeamDescriptionAndMemberNames do
  use Ecto.Migration

  def change do
    alter table(:teams) do
      add :description, :string
    end

    alter table(:team_members) do
      add :first_name, :string
      add :last_name, :string
    end
  end
end
