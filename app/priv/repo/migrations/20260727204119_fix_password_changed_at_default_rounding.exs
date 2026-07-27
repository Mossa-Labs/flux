defmodule Flux.Repo.Migrations.FixPasswordChangedAtDefaultRounding do
  use Ecto.Migration

  # `users.password_changed_at` is written from two places that disagreed twice
  # over — on TIME ZONE and on rounding.
  #
  # Registration does not set the column: it goes through `email_changeset`, and
  # only the password changeset stamps it. So the column default is the real
  # insert-time writer, and it has to agree with the application.
  #
  # 1. TIME ZONE. The column is `timestamp WITHOUT time zone` and the default was
  #    `now()`, which returns the server's LOCAL wall clock. Ecto maps the field
  #    as `:utc_datetime` and loads it as UTC, so on any server not set to UTC
  #    every stamp was silently wrong by that server's offset — on a UTC-4 host,
  #    four hours in the past.
  #
  # 2. ROUNDING. The column is `timestamp(0)`, which ROUNDS to the nearest second
  #    (12:00:00.9 stores as 12:00:01), while `User.maybe_hash_password/2` writes
  #    `DateTime.utc_now(:second)`, which TRUNCATES (12:00:00.9 becomes 12:00:00).
  #    A user registered in the second half of a second whose password changes
  #    within that same second gets a rotation stamp EARLIER than the one
  #    recorded at insert — "password changed before the account existed".
  #
  # On a non-UTC server the offset from (1) masked (2), which is why the MOS-590
  # rotation test passed locally and failed in CI, where Postgres runs UTC.
  #
  # `now() AT TIME ZONE 'utc'` fixes the first, `date_trunc('second', ...)` the
  # second, leaving the default consistent with what the application writes.

  def up do
    execute """
    ALTER TABLE users
      ALTER COLUMN password_changed_at
      SET DEFAULT date_trunc('second', now() AT TIME ZONE 'utc')
    """
  end

  def down do
    execute """
    ALTER TABLE users
      ALTER COLUMN password_changed_at
      SET DEFAULT now()
    """
  end
end
