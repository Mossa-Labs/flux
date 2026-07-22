defmodule Flux.Sinks.SecretEncryptionTest do
  @moduledoc """
  End-to-end coverage for field-level encryption of sink secrets at rest
  (MOS-587): secrets are ciphertext in the DB, plaintext to callers, and the
  "leave blank keeps the existing secret" edit flow (MOS-556) still works.
  """
  use Flux.DataCase

  alias Flux.Repo
  alias Flux.Sinks
  alias Flux.Vault

  import Flux.AccountsFixtures

  setup do
    scope = user_scope_fixture()
    %{org_id: scope.organization_id}
  end

  defp http_config(token) do
    %{
      "url" => "https://example.com/webhook",
      "method" => "POST",
      "auth" => %{"type" => "bearer", "token" => token}
    }
  end

  # Reads the config column straight from Postgres, bypassing the Ecto type, so
  # we see exactly what is persisted on disk.
  defp raw_config(sink_id) do
    %{rows: [[config]]} =
      Repo.query!("SELECT config FROM sinks WHERE id = $1", [sink_id])

    config
  end

  test "secret fields are ciphertext at rest but plaintext to callers", %{org_id: org_id} do
    {:ok, sink} =
      Sinks.create_sink(%{
        name: "enc-sink",
        type: "http",
        organization_id: org_id,
        config: http_config("super-secret-token")
      })

    raw = raw_config(sink.id)

    # On disk: token is an encrypted wrapper, url is untouched plaintext.
    assert %{"encrypted" => true, "ciphertext" => ct} = raw["auth"]["token"]
    refute ct =~ "super-secret-token"
    assert raw["url"] == "https://example.com/webhook"

    # To callers: transparent plaintext.
    reloaded = Sinks.get_sink(sink.id, org_id)
    assert reloaded.config["auth"]["token"] == "super-secret-token"
  end

  test "editing without re-entering the secret preserves it (MOS-556)", %{org_id: org_id} do
    {:ok, sink} =
      Sinks.create_sink(%{
        name: "edit-sink",
        type: "http",
        organization_id: org_id,
        config: http_config("original-secret")
      })

    # Simulate the form re-submitting the loaded (decrypted) config with an
    # unrelated change; the secret rides along in plaintext and is re-encrypted.
    loaded = Sinks.get_sink(sink.id, org_id)
    updated_config = put_in(loaded.config, ["method"], "PUT")

    {:ok, updated} = Sinks.update_sink(loaded, %{config: updated_config})

    assert updated.config["auth"]["token"] == "original-secret"
    assert updated.config["method"] == "PUT"
    assert %{"encrypted" => true} = raw_config(updated.id)["auth"]["token"]
  end

  test "load tolerates a legacy plaintext row (no re-encryption needed to read)", %{
    org_id: org_id
  } do
    {:ok, sink} =
      Sinks.create_sink(%{
        name: "legacy-sink",
        type: "http",
        organization_id: org_id,
        config: http_config("x")
      })

    # Force a plaintext secret directly into the DB, as if written before
    # encryption existed.
    plaintext = %{"url" => "https://e.com", "auth" => %{"type" => "bearer", "token" => "legacy"}}
    Repo.query!("UPDATE sinks SET config = $1 WHERE id = $2", [plaintext, sink.id])

    reloaded = Sinks.get_sink(sink.id, org_id)
    assert reloaded.config["auth"]["token"] == "legacy"
  end

  test "a ciphertext relocated into a non-secret field is not decrypted (no oracle)", %{
    org_id: org_id
  } do
    # Simulate an attacker who holds a stolen ciphertext (from a leaked DB
    # snapshot) but not the key, pasting it into a non-secret config field.
    stolen = Vault.encrypt_value("stolen-secret")

    {:ok, sink} =
      Sinks.create_sink(%{
        name: "oracle-sink",
        type: "postgres",
        organization_id: org_id,
        config: %{
          "database_url" => "postgres://u:pw@h:5432/db",
          "table" => "events",
          "columns" => %{"x" => stolen}
        }
      })

    reloaded = Sinks.get_sink(sink.id, org_id)

    # The wrapper in the non-secret `columns` field is NOT decrypted.
    assert reloaded.config["columns"]["x"] == stolen
    refute reloaded.config["columns"]["x"] == "stolen-secret"

    # And redaction scrubs the residual wrapper so it never even echoes back.
    redacted = Sinks.redact_config(reloaded.config)
    assert redacted["columns"]["x"] == "[REDACTED]"
  end
end
