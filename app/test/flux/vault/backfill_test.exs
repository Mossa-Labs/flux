defmodule Flux.Vault.BackfillTest do
  @moduledoc """
  Covers `Flux.Vault.Backfill`, the routine behind the MOS-654 data migrations
  that move existing rows onto encrypted secret fields. The migrations
  themselves are one-line calls into it.
  """
  use Flux.DataCase

  alias Flux.Repo
  alias Flux.Sources.Source
  alias Flux.Vault.Backfill

  import Flux.AccountsFixtures

  @plain %{"host" => "sftp.example.com", "password" => "hunter2", "auth" => %{"token" => "t"}}

  setup do
    scope = user_scope_fixture()

    source =
      Repo.insert!(%Source{
        name: "legacy",
        type: "sftp",
        organization_id: scope.organization_id,
        config: %{"host" => "x"}
      })

    # Force a pre-encryption (plaintext) row.
    Repo.query!("UPDATE sources SET config = $1 WHERE id = $2", [@plain, source.id])

    %{source: source}
  end

  defp raw_config(id) do
    %{rows: [[config]]} = Repo.query!("SELECT config FROM sources WHERE id = $1", [id])
    config
  end

  test "encrypt then decrypt round-trips a legacy row, and is idempotent", %{source: source} do
    assert Backfill.run(Repo, "sources", "config", Flux.Sources.Secrets, :encrypt) == 1
    raw = raw_config(source.id)
    assert %{"encrypted" => true} = raw["password"]
    assert %{"encrypted" => true} = raw["auth"]["token"]
    assert raw["host"] == "sftp.example.com"

    # Already encrypted: nothing left to change.
    assert Backfill.run(Repo, "sources", "config", Flux.Sources.Secrets, :encrypt) == 0

    assert Backfill.run(Repo, "sources", "config", Flux.Sources.Secrets, :decrypt) == 1
    assert raw_config(source.id) == @plain
    assert Backfill.run(Repo, "sources", "config", Flux.Sources.Secrets, :decrypt) == 0
  end

  test "a save that lands between read and write is kept, not overwritten", %{source: source} do
    newer = %{"host" => "sftp2.example.com", "password" => "rotated"}

    Flux.RacingRepo.race_before_next_update(fn ->
      Repo.query!("UPDATE sources SET config = $1 WHERE id = $2", [newer, source.id])
    end)

    assert Backfill.run(Flux.RacingRepo, "sources", "config", Flux.Sources.Secrets, :encrypt) == 1

    raw = raw_config(source.id)
    assert raw["host"] == "sftp2.example.com"
    assert %{"encrypted" => true} = raw["password"]
    assert Repo.get!(Source, source.id).config == newer
  end

  test "a row deleted between read and write is skipped", %{source: source} do
    Flux.RacingRepo.race_before_next_update(fn ->
      Repo.query!("DELETE FROM sources WHERE id = $1", [source.id])
    end)

    assert Backfill.run(Flux.RacingRepo, "sources", "config", Flux.Sources.Secrets, :encrypt) == 0
  end

  test "a config whose auth is not a map is encrypted without raising", %{source: source} do
    legacy = %{"password" => "hunter2", "auth" => "none"}
    Repo.query!("UPDATE sources SET config = $1 WHERE id = $2", [legacy, source.id])

    assert Backfill.run(Repo, "sources", "config", Flux.Sources.Secrets, :encrypt) == 1
    raw = raw_config(source.id)
    assert %{"encrypted" => true} = raw["password"]
    assert raw["auth"] == "none"
  end
end
