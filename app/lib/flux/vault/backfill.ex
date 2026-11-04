defmodule Flux.Vault.Backfill do
  @moduledoc """
  Encrypts or decrypts the secret fields of one JSONB column across a whole
  table, for data migrations that move a column on or off
  `Flux.Vault.EncryptedConfig`.

  Works on raw rows (`SELECT id, <column>`), never through an Ecto schema: a
  schema whose field already uses `EncryptedConfig` would decrypt on load and
  hide what is actually on disk. Rows are walked in primary-key order, in
  batches, and a row is only written when its value actually changes.

  Both directions are idempotent — encryption skips existing wrappers, and
  decryption passes plaintext through — so a re-run is harmless.
  """

  alias Flux.Vault

  @batch_size 500

  @doc """
  Rewrites `column` of every row in `table`, encrypting (`:encrypt`) or
  decrypting (`:decrypt`) the secret paths named by the `secrets` module (a
  `Flux.Vault.SecretPaths`). Returns the number of rows changed.

  `table` and `column` are trusted identifiers from migration code, never user
  input.
  """
  @spec run(Ecto.Repo.t(), String.t(), String.t(), module(), :encrypt | :decrypt) ::
          non_neg_integer()
  def run(repo, table, column, secrets, direction) when direction in [:encrypt, :decrypt] do
    select = "SELECT id, #{column} FROM #{table} WHERE id > $1 ORDER BY id LIMIT $2"
    update = "UPDATE #{table} SET #{column} = $1 WHERE id = $2"

    Stream.unfold(0, fn last_id ->
      case repo.query!(select, [last_id, @batch_size]).rows do
        [] -> nil
        rows -> {rows, rows |> List.last() |> hd()}
      end
    end)
    |> Stream.flat_map(& &1)
    |> Enum.reduce(0, fn [id, value], changed ->
      new_value = transform(value, secrets, direction)

      if new_value == value do
        changed
      else
        repo.query!(update, [new_value, id])
        changed + 1
      end
    end)
  end

  defp transform(value, secrets, :encrypt) when is_map(value),
    do: Vault.encrypt_map(value, secrets.paths(value))

  defp transform(value, secrets, :decrypt) when is_map(value),
    do: Vault.decrypt_map(value, secrets.paths(value))

  defp transform(value, _secrets, _direction), do: value
end
