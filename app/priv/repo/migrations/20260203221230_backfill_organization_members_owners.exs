defmodule Flux.Repo.Migrations.BackfillOrganizationMembersOwners do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO organization_members (organization_id, user_id, role, inserted_at, updated_at)
    SELECT id, user_id, 'owner', NOW(), NOW()
    FROM organizations
    WHERE user_id IS NOT NULL
    ON CONFLICT (organization_id, user_id) DO NOTHING
    """)
  end

  def down do
    # No-op: backfill is additive; down would require tracking which rows we inserted.
  end
end
