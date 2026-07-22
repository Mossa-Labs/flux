defmodule Flux.Vault.EncryptedConfigTest do
  use ExUnit.Case, async: true

  alias Flux.Vault.EncryptedConfig

  @config %{
    "url" => "https://example.com",
    "database_url" => "postgres://u:pw@h/db",
    "auth" => %{"type" => "bearer", "token" => "abc123"}
  }

  test "type/0 is :map" do
    assert EncryptedConfig.type() == :map
  end

  test "cast/1 accepts maps and nil, rejects others" do
    assert EncryptedConfig.cast(%{"a" => 1}) == {:ok, %{"a" => 1}}
    assert EncryptedConfig.cast(nil) == {:ok, nil}
    assert EncryptedConfig.cast("nope") == :error
  end

  test "dump encrypts secrets, keeps non-secret keys plaintext" do
    {:ok, dumped} = EncryptedConfig.dump(@config)

    assert dumped["url"] == "https://example.com"
    assert %{"encrypted" => true} = dumped["database_url"]
    assert %{"encrypted" => true} = dumped["auth"]["token"]
  end

  test "dump then load round-trips to the original plaintext" do
    {:ok, dumped} = EncryptedConfig.dump(@config)
    {:ok, loaded} = EncryptedConfig.load(dumped)
    assert loaded == @config
  end

  test "load passes legacy plaintext rows through unchanged" do
    {:ok, loaded} = EncryptedConfig.load(@config)
    assert loaded == @config
  end

  test "nil round-trips" do
    assert EncryptedConfig.dump(nil) == {:ok, nil}
    assert EncryptedConfig.load(nil) == {:ok, nil}
  end
end
