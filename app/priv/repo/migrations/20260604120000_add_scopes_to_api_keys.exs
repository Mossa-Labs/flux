defmodule Flux.Repo.Migrations.AddScopesToApiKeys do
  use Ecto.Migration

  def change do
    # OAuth-style resource scopes granted to a key (e.g. "read:pipelines").
    # Defaults to an empty list; the context backfills role-derived defaults on
    # create, and existing rows are treated as "all scopes for the role" at read
    # time for backwards compatibility.
    alter table(:api_keys) do
      add :scopes, {:array, :string}, null: false, default: []
    end
  end
end
