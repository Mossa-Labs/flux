defmodule Flux.Repo.Migrations.EncryptSourceConfigSecrets do
  @moduledoc """
  Encrypts the secret fields of every existing `sources.config` at rest
  (MOS-654). `Flux.Sources.Source` now reads the column through
  `Flux.Vault.EncryptedConfig`, which already tolerates legacy plaintext, so
  this only closes the window for rows that are never re-saved.

  `down` decrypts again, so rolling back to code that reads `config` as a plain
  map does not hand ciphertext to the source adapters. Run the rollback before
  deploying the older code.
  """
  use Ecto.Migration

  def up do
    Flux.Vault.Backfill.run(repo(), "sources", "config", Flux.Sources.Secrets, :encrypt)
  end

  def down do
    Flux.Vault.Backfill.run(repo(), "sources", "config", Flux.Sources.Secrets, :decrypt)
  end
end
