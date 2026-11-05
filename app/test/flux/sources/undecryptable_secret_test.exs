defmodule Flux.Sources.UndecryptableSecretTest do
  @moduledoc """
  A stored source secret that can't be decrypted with the current vault key
  loads as a marker map (see `Flux.Vault.decrypt_map/2`). MOS-666: such a
  source is refused with `{:error, :undecryptable_secret}` before any adapter
  code runs, and it can still be disabled.
  """
  use Flux.DataCase, async: true

  import ExUnit.CaptureLog
  import Flux.AccountsFixtures
  import Flux.SourcesFixtures

  alias Flux.Repo
  alias Flux.Sources
  alias Flux.Sources.Source

  setup do
    scope = user_scope_fixture()
    %{org_id: scope.organization_id}
  end

  # Reads the config column straight from Postgres, bypassing the Ecto type.
  defp raw_config(source_id) do
    %{rows: [[config]]} = Repo.query!("SELECT config FROM sources WHERE id = $1", [source_id])
    config
  end

  # Registers the recording adapter under a test-unique type, so async tests
  # never overwrite a shared one.
  defp register_recording_type do
    type = "recording_#{System.unique_integer([:positive])}"
    :ok = Flux.Source.Registry.register(type, Flux.Test.RecordingSourceAdapter)
    type
  end

  describe "undecryptable_secrets/1" do
    test "names the affected keys", %{org_id: org_id} do
      bad = undecryptable_source_fixture(org_id)
      good = source_fixture(org_id)

      assert Sources.undecryptable_secrets(bad) == ["secret_access_key"]
      assert Sources.undecryptable_secrets?(bad)
      assert Sources.undecryptable_secrets(good) == []
      refute Sources.undecryptable_secrets?(good)
    end

    test "names nested auth keys with a dotted path", %{org_id: org_id} do
      source =
        org_id
        |> source_fixture(
          type: "webhook",
          config: %{"source" => "github", "auth" => %{"type" => "bearer", "token" => "t"}}
        )
        |> make_secret_undecryptable(["auth", "token"])

      assert Sources.undecryptable_secrets(source) == ["auth.token"]
    end
  end

  describe "start_ingestion/1" do
    test "refuses the source and logs the id and key names, never ciphertext",
         %{org_id: org_id} do
      source = undecryptable_source_fixture(org_id)
      ciphertext = raw_config(source.id)["secret_access_key"]["ciphertext"]

      log =
        capture_log(fn ->
          assert Sources.start_ingestion(source) == {:error, :undecryptable_secret}
        end)

      assert log =~ "sqs source #{source.id}"
      assert log =~ "secret_access_key"
      refute log =~ ciphertext
    end

    test "starts a source whose secrets all decrypt", %{org_id: org_id} do
      assert Sources.start_ingestion(source_fixture(org_id)) == {:ok, :passive}
    end
  end

  describe "test_connection/1" do
    test "returns :undecryptable_secret", %{org_id: org_id} do
      source = undecryptable_source_fixture(org_id)
      assert Sources.test_connection(source) == {:error, :undecryptable_secret}
    end
  end

  describe "the adapter never receives a marker" do
    setup %{org_id: org_id} do
      type = register_recording_type()
      %{type: type, source: undecryptable_source_fixture(org_id, type: type)}
    end

    test "when starting the source", %{type: type, source: source} do
      capture_log(fn ->
        assert Flux.Source.Supervisor.start_source(type, source.config, source_id: source.id) ==
                 {:error, :undecryptable_secret}
      end)

      refute_received {:source_adapter_called, _callback, _config}
    end

    test "when testing the connection", %{type: type, source: source} do
      assert Flux.Source.test_connection(type, source.config) == {:error, :undecryptable_secret}
      refute_received {:source_adapter_called, _callback, _config}
    end

    test "when the manager walks enabled sources at boot", %{type: type, source: source} do
      log = capture_log(fn -> Flux.Source.Manager.handle_info(:auto_start, %{}) end)

      assert log =~ "#{type} source #{source.id}"
      assert log =~ "secret_access_key"
      refute_received {:source_adapter_called, _callback, _config}
    end

    test "while a healthy source of the same type does reach it",
         %{org_id: org_id, type: type} do
      healthy = source_fixture(org_id, type: type)

      assert Sources.start_ingestion(healthy) == {:ok, :passive}

      assert_received {:source_adapter_called, :ingestion_spec,
                       %{"secret_access_key" => "old-secret-key"}}
    end
  end

  describe "changeset" do
    setup %{org_id: org_id} do
      type = register_recording_type()
      %{source: undecryptable_source_fixture(org_id, type: type)}
    end

    test "disabling or renaming skips validation and keeps the stored ciphertext",
         %{source: source} do
      stored = raw_config(source.id)["secret_access_key"]

      assert {:ok, disabled} = Sources.toggle_enabled(source)
      refute disabled.enabled
      assert {:ok, renamed} = Sources.update_source(disabled, %{name: "renamed"})
      assert renamed.name == "renamed"

      assert raw_config(source.id)["secret_access_key"] == stored
      refute_received {:source_adapter_called, :validate_config, _config}
    end

    test "a config change that keeps the marker asks for the secret again",
         %{source: source} do
      config = Map.put(source.config, "region", "eu-west-1")

      assert {:error, changeset} = Sources.update_source(source, %{config: config})

      assert "secret_access_key can't be decrypted with the current vault key; re-enter it" in errors_on(
               changeset
             ).config

      refute_received {:source_adapter_called, :validate_config, _config}
    end

    test "re-entering the secret saves it", %{source: source} do
      config = Map.put(source.config, "secret_access_key", "new-key")

      assert {:ok, _updated} = Sources.update_source(source, %{config: config})

      assert_received {:source_adapter_called, :validate_config,
                       %{"secret_access_key" => "new-key"}}

      reloaded = Repo.get!(Source, source.id)
      assert reloaded.config["secret_access_key"] == "new-key"
      refute Sources.undecryptable_secrets?(reloaded)
    end
  end
end
