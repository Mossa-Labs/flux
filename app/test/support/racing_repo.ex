defmodule Flux.RacingRepo do
  @moduledoc """
  A stand-in for `Flux.Repo` that can run a concurrent-looking write between a
  read and the next `UPDATE`, to test code that must not lose another writer's
  save (e.g. `Flux.Vault.Backfill`).

  Arm it with `race_before_next_update/1`: the given function runs once, right
  before the next `UPDATE` statement is sent. Everything else is delegated to
  `Flux.Repo`.
  """

  @key {__MODULE__, :before_update}

  @doc "Runs `fun` once, right before the next `UPDATE` this process sends."
  def race_before_next_update(fun) when is_function(fun, 0), do: Process.put(@key, fun)

  def query!(sql, params) do
    if String.starts_with?(sql, "UPDATE") do
      case Process.delete(@key) do
        nil -> :ok
        fun -> fun.()
      end
    end

    Flux.Repo.query!(sql, params)
  end
end
