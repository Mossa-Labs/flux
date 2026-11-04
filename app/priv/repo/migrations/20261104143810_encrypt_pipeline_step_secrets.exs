defmodule Flux.Repo.Migrations.EncryptPipelineStepSecrets do
  @moduledoc """
  Encrypts the source credentials the pipeline builder keeps in
  `nodes[].sourceConfig` of every existing `pipelines.steps` and
  `pipeline_versions.steps` (MOS-654). Both schemas now read `steps` through
  `Flux.Vault.EncryptedConfig`, which tolerates legacy plaintext, so this only
  closes the window for rows that are never re-saved — notably version
  snapshots, which are immutable.

  `down` decrypts again, so rolling back to code that reads `steps` as a plain
  map does not hand ciphertext to the builder or the runner. Run the rollback
  before deploying the older code.
  """
  use Ecto.Migration

  @tables ~w(pipelines pipeline_versions)

  def up do
    for table <- @tables,
        do: Flux.Vault.Backfill.run(repo(), table, "steps", Flux.Pipelines.StepSecrets, :encrypt)
  end

  def down do
    for table <- @tables,
        do: Flux.Vault.Backfill.run(repo(), table, "steps", Flux.Pipelines.StepSecrets, :decrypt)
  end
end
