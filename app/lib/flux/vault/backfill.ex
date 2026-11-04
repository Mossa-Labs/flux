defmodule Flux.Vault.Backfill do
  @moduledoc """
  Encrypts or decrypts the secret fields of one JSONB column across a whole
  table, for data migrations that move a column on or off
  `Flux.Vault.EncryptedConfig`.

  Works on raw rows (`SELECT id, <column>`), never through an Ecto schema: a
  schema whose field already uses `EncryptedConfig` would decrypt on load and
  hide what is actually on disk. Rows are walked in primary-key order, in
  batches, and a row is only written when its value actually changes.

  Writes are compare-and-swap: the `UPDATE` only applies while the row still
  holds the value that was read. If the application saves the row in between,
  the row is re-read and transformed again, so a concurrent save is never
  overwritten with the older value.

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
    reread = "SELECT #{column} FROM #{table} WHERE id = $1"
    update = "UPDATE #{table} SET #{column} = $1 WHERE id = $2 AND #{column} = $3"

    Stream.unfold(0, fn last_id ->
      case repo.query!(select, [last_id, @batch_size]).rows do
        [] -> nil
        rows -> {rows, rows |> List.last() |> hd()}
      end
    end)
    |> Stream.flat_map(& &1)
    |> Enum.reduce(0, fn [id, value], changed ->
      changed + rewrite(repo, {reread, update}, id, value, secrets, direction)
    end)
  end

  # Returns 1 when the row was rewritten, 0 when it needed no change (or was
  # deleted meanwhile).
  defp rewrite(_repo, _sql, _id, nil, _secrets, _direction), do: 0

  defp rewrite(repo, {reread, update} = sql, id, value, secrets, direction) do
    new_value = transform(value, secrets, direction)

    cond do
      new_value == value ->
        0

      repo.query!(update, [new_value, id, value]).num_rows == 1 ->
        1

      # The row changed after it was read: start over from what is there now.
      true ->
        current =
          case repo.query!(reread, [id]).rows do
            [[current]] -> current
            [] -> nil
          end

        rewrite(repo, sql, id, current, secrets, direction)
    end
  end

  defp transform(value, secrets, :encrypt) when is_map(value),
    do: Vault.encrypt_map(value, secrets.paths(value))

  defp transform(value, secrets, :decrypt) when is_map(value),
    do: Vault.decrypt_map(value, secrets.paths(value))

  defp transform(value, _secrets, _direction), do: value
end
