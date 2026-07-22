defmodule Mix.Tasks.Flux.Vault.EncryptSinks do
  @shortdoc "Encrypts secret fields of all existing sink configs at rest"

  @moduledoc """
  One-time backfill that re-writes every sink so its secret `config` fields are
  encrypted at rest by `Flux.Vault.EncryptedConfig`.

  Reads already work without this task — legacy plaintext passes through on load,
  and any subsequent save encrypts automatically. Run this once to encrypt rows
  that have not been re-saved since encryption was introduced.

  Idempotent: re-running re-encrypts (previously-encrypted values are decrypted
  on load and re-encrypted on write) and is harmless.

  ## Examples

      mix flux.vault.encrypt_sinks
      mix flux.vault.encrypt_sinks --dry-run
  """

  use Mix.Task

  import Ecto.Changeset, only: [change: 1, force_change: 3]

  alias Flux.Repo
  alias Flux.Sinks.Sink

  @switches [dry_run: :boolean]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _rest, _} = OptionParser.parse(args, strict: @switches)
    dry_run? = Keyword.get(opts, :dry_run, false)

    sinks = Repo.all(Sink)
    Mix.shell().info("Found #{length(sinks)} sink(s) to encrypt#{if dry_run?, do: " (dry run)"}.")

    {ok, failed} =
      Enum.reduce(sinks, {0, 0}, fn sink, {ok, failed} ->
        if dry_run? do
          {ok + 1, failed}
        else
          # `change/1` runs no validations; `force_change/3` guarantees the
          # config column is dumped (and therefore encrypted) even though the
          # decrypted value is byte-equal to what was loaded.
          case sink |> change() |> force_change(:config, sink.config) |> Repo.update() do
            {:ok, _} ->
              {ok + 1, failed}

            {:error, changeset} ->
              Mix.shell().error("  sink ##{sink.id} failed: #{inspect(changeset.errors)}")
              {ok, failed + 1}
          end
        end
      end)

    Mix.shell().info("Done. #{ok} encrypted, #{failed} failed.")
    if failed > 0, do: exit({:shutdown, 1})
  end
end
