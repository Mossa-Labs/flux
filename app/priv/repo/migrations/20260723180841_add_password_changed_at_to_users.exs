defmodule Flux.Repo.Migrations.AddPasswordChangedAtToUsers do
  use Ecto.Migration

  # Tracks when a user's password was last set, so an org's rotation policy
  # (MOS-590) can decide whether the password is expired at login. Backfills
  # existing rows to migration time — the rotation clock starts now rather than
  # instantly expiring everyone. The password changeset keeps this current.
  def change do
    alter table(:users) do
      add :password_changed_at, :utc_datetime, null: false, default: fragment("now()")
    end
  end
end
