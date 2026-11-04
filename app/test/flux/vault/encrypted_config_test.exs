defmodule Flux.Vault.EncryptedConfigTest do
  use ExUnit.Case, async: true

  alias Flux.Vault.EncryptedConfig

  @config %{
    "url" => "https://example.com",
    "database_url" => "postgres://u:pw@h/db",
    "auth" => %{"type" => "bearer", "token" => "abc123"}
  }

  setup do
    %{params: EncryptedConfig.init(secrets: Flux.Sinks.Secrets)}
  end

  test "init/1 requires a secrets module" do
    assert_raise ArgumentError, ~r/secrets/, fn -> EncryptedConfig.init([]) end
  end

  test "type/1 is :map", %{params: params} do
    assert EncryptedConfig.type(params) == :map
  end

  test "cast/2 accepts maps and nil, rejects others", %{params: params} do
    assert EncryptedConfig.cast(%{"a" => 1}, params) == {:ok, %{"a" => 1}}
    assert EncryptedConfig.cast(nil, params) == {:ok, nil}
    assert EncryptedConfig.cast("nope", params) == :error
  end

  test "dump encrypts secrets, keeps non-secret keys plaintext", %{params: params} do
    {:ok, dumped} = EncryptedConfig.dump(@config, nil, params)

    assert dumped["url"] == "https://example.com"
    assert %{"encrypted" => true} = dumped["database_url"]
    assert %{"encrypted" => true} = dumped["auth"]["token"]
  end

  test "dump then load round-trips to the original plaintext", %{params: params} do
    {:ok, dumped} = EncryptedConfig.dump(@config, nil, params)
    {:ok, loaded} = EncryptedConfig.load(dumped, nil, params)
    assert loaded == @config
  end

  test "load passes legacy plaintext rows through unchanged", %{params: params} do
    {:ok, loaded} = EncryptedConfig.load(@config, nil, params)
    assert loaded == @config
  end

  test "nil round-trips", %{params: params} do
    assert EncryptedConfig.dump(nil, nil, params) == {:ok, nil}
    assert EncryptedConfig.load(nil, nil, params) == {:ok, nil}
  end

  test "the secrets module decides which paths are encrypted" do
    params = EncryptedConfig.init(secrets: Flux.Sources.Secrets)
    config = %{"host" => "sftp.example.com", "private_key" => "-----BEGIN KEY-----"}

    {:ok, dumped} = EncryptedConfig.dump(config, nil, params)

    assert dumped["host"] == "sftp.example.com"
    assert %{"encrypted" => true} = dumped["private_key"]
    assert {:ok, ^config} = EncryptedConfig.load(dumped, nil, params)
  end

  test "load doesn't raise when a secret was encrypted under another key", %{params: params} do
    foreign = Flux.SinksFixtures.foreign_encrypted_wrapper("abc123")
    stored = put_in(@config, ["auth", "token"], foreign)

    assert {:ok, loaded} = EncryptedConfig.load(stored, nil, params)
    assert loaded["url"] == "https://example.com"
    assert loaded["database_url"] == "postgres://u:pw@h/db"
    assert Flux.Vault.undecryptable?(loaded["auth"]["token"])

    # Writing the row back keeps the original ciphertext, minus the flag.
    assert {:ok, dumped} = EncryptedConfig.dump(loaded, nil, params)
    assert dumped["auth"]["token"] == foreign
  end
end
