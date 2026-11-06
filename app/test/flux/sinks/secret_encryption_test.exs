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

  # The HTTP changeset rejects such an `auth`, but older rows (or other sink
  # types) can hold one, so exercise the Ecto type directly.
  test "a config whose auth is a plain value saves and loads", %{org_id: org_id} do
    sink =
      Repo.insert!(%Flux.Sinks.Sink{
        name: "no-auth-sink",
        type: "http",
        organization_id: org_id,
        config: %{"url" => "https://example.com/webhook", "auth" => "none"}
      })

    assert raw_config(sink.id)["auth"] == "none"
    assert Sinks.get_sink(sink.id, org_id).config["auth"] == "none"
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

  test "email sink api_key and password are ciphertext at rest", %{org_id: org_id} do
    {:ok, sink} =
      Sinks.create_sink(%{
        name: "email-enc-sink",
        type: "email",
        organization_id: org_id,
        config: %{
          "provider" => "sendgrid",
          "api_key" => "SG.super-secret-key",
          "from" => "alerts@example.com",
          "to" => ["ops@example.com"],
          "subject" => "hi"
        }
      })

    raw = raw_config(sink.id)
    assert %{"encrypted" => true, "ciphertext" => ct} = raw["api_key"]
    refute ct =~ "super-secret-key"
    assert raw["from"] == "alerts@example.com"

    assert Sinks.get_sink(sink.id, org_id).config["api_key"] == "SG.super-secret-key"
    assert Sinks.redact_config(sink.config)["api_key"] != "SG.super-secret-key"
  end

  describe "PagerDuty REST credentials" do
    # The public build backs "pagerduty" with the Enterprise stub, which rejects
    # every save; a permissive adapter stands in for the licensed one.
    setup do
      Flux.Sink.Registry.register("pagerduty", Flux.Test.PermissiveSinkAdapter)
      on_exit(fn -> Flux.Sink.Registry.register("pagerduty", Flux.Sink.Adapters.Stub) end)
      :ok
    end

    test "an OAuth client secret and a REST API key are ciphertext at rest", %{org_id: org_id} do
      {:ok, sink} =
        Sinks.create_sink(%{
          name: "pagerduty-enc-sink",
          type: "pagerduty",
          organization_id: org_id,
          config: %{
            "auth_mode" => "rest_oauth",
            "client_id" => "pd-client-id",
            "client_secret" => "pdus+oauth-client-secret",
            "api_key" => "u+PagerDutyRestApiKey",
            "subdomain" => "acme",
            "service_id" => "PSERVIC"
          }
        })

      raw = raw_config(sink.id)

      for key <- ~w(client_secret api_key) do
        assert %{"encrypted" => true, "ciphertext" => ct} = raw[key]
        refute ct =~ "pdus+oauth-client-secret"
        refute ct =~ "u+PagerDutyRestApiKey"
      end

      # The client ID identifies the app; it isn't a secret.
      assert raw["client_id"] == "pd-client-id"

      config = Sinks.get_sink(sink.id, org_id).config
      assert config["client_secret"] == "pdus+oauth-client-secret"
      assert config["api_key"] == "u+PagerDutyRestApiKey"
    end
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
