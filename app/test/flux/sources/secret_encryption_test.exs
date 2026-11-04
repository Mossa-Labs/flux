defmodule Flux.Sources.SecretEncryptionTest do
  @moduledoc """
  End-to-end coverage for field-level encryption of source secrets at rest
  (MOS-654): secrets are ciphertext in the DB, plaintext to callers and
  adapters, and masked on the way out.
  """
  use Flux.DataCase

  alias Flux.Repo
  alias Flux.Sources
  alias Flux.Sources.Source
  alias Flux.Vault

  import Flux.AccountsFixtures

  setup do
    scope = user_scope_fixture()
    %{org_id: scope.organization_id}
  end

  # Pro/EE source types don't validate in the Community build (their adapters
  # are stubs), so insert the struct directly. The Ecto type still runs on
  # dump/load, which is what is under test.
  defp insert_source!(org_id, type, config) do
    Repo.insert!(%Source{
      name: "#{type}-#{System.unique_integer([:positive])}",
      type: type,
      organization_id: org_id,
      config: config
    })
  end

  # Reads the config column straight from Postgres, bypassing the Ecto type, so
  # we see exactly what is persisted on disk.
  defp raw_config(source_id) do
    %{rows: [[config]]} = Repo.query!("SELECT config FROM sources WHERE id = $1", [source_id])
    config
  end

  @sftp %{
    "host" => "sftp.example.com",
    "username" => "flux",
    "password" => "hunter2",
    "private_key" => "-----BEGIN OPENSSH PRIVATE KEY-----",
    "passphrase" => "s3cret"
  }

  @grpc %{
    "mode" => "client",
    "endpoint" => "telemetry.example.com:443",
    "bearer_token" => "t0k",
    "client_cert" => "-----BEGIN CERTIFICATE-----",
    "client_key" => "-----BEGIN PRIVATE KEY-----",
    "metadata" => %{"authorization" => "Bearer abc", "x-tenant" => "acme"}
  }

  @sqs %{
    "queue_url" => "https://sqs.us-east-1.amazonaws.com/1/q",
    "access_key_id" => "AKIA123",
    "secret_access_key" => "aws-secret",
    "session_token" => "aws-session"
  }

  test "secret fields are ciphertext at rest, non-secret fields stay plaintext", %{org_id: org_id} do
    for {type, config, secrets, plain} <- [
          {"sftp", @sftp, ~w(password private_key passphrase), ~w(host username)},
          {"grpc", @grpc, ~w(bearer_token client_key metadata), ~w(mode endpoint client_cert)},
          {"sqs", @sqs, ~w(secret_access_key session_token), ~w(queue_url access_key_id)}
        ] do
      source = insert_source!(org_id, type, config)
      raw = raw_config(source.id)

      for key <- secrets do
        assert %{"encrypted" => true, "ciphertext" => ct} = raw[key],
               "#{type}.#{key} not encrypted"

        refute ct =~ inspect(config[key])
      end

      for key <- plain, do: assert(raw[key] == config[key], "#{type}.#{key} changed on disk")
    end
  end

  test "readers and adapters see plaintext", %{org_id: org_id} do
    source = insert_source!(org_id, "grpc", @grpc)

    assert Sources.get_source(source.id, org_id).config == @grpc
    assert Sources.get_source!(source.id).config == @grpc

    assert [loaded] = Enum.filter(Sources.list_all_enabled_sources(), &(&1.id == source.id))
    # A map-valued secret (gRPC metadata) round-trips as a map.
    assert loaded.config["metadata"] == %{"authorization" => "Bearer abc", "x-tenant" => "acme"}
  end

  test "re-saving a loaded config keeps the secret and keeps it encrypted", %{org_id: org_id} do
    source = insert_source!(org_id, "sftp", @sftp)
    loaded = Sources.get_source(source.id, org_id)

    {:ok, updated} =
      loaded
      |> Ecto.Changeset.change(config: Map.put(loaded.config, "host", "sftp2.example.com"))
      |> Repo.update()

    assert updated.config["password"] == "hunter2"
    raw = raw_config(updated.id)
    assert raw["host"] == "sftp2.example.com"
    assert %{"encrypted" => true} = raw["password"]
  end

  test "webhook sources created through the context are unaffected", %{org_id: org_id} do
    {:ok, source} =
      Sources.create_source(%{
        "name" => "hook",
        "type" => "webhook",
        "config" => %{"source" => "github"},
        "organization_id" => org_id
      })

    assert raw_config(source.id) == %{"source" => "github"}
    assert Sources.queue_name(source) == "webhooks.github"
  end

  test "a legacy plaintext row loads without re-encryption", %{org_id: org_id} do
    source = insert_source!(org_id, "sftp", %{"host" => "h"})
    Repo.query!("UPDATE sources SET config = $1 WHERE id = $2", [@sftp, source.id])

    assert Sources.get_source(source.id, org_id).config == @sftp
  end

  test "a ciphertext relocated into a non-secret field is not decrypted (no oracle)", %{
    org_id: org_id
  } do
    stolen = Vault.encrypt_value("stolen-secret")
    source = insert_source!(org_id, "sftp", Map.put(@sftp, "archive_path", stolen))

    reloaded = Sources.get_source(source.id, org_id)
    assert reloaded.config["archive_path"] == stolen

    redacted = Sources.redact_config(reloaded.config)
    assert redacted["archive_path"] == "[REDACTED]"
    assert redacted["password"] == "[REDACTED]"
  end
end
