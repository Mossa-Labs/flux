defmodule Flux.VaultTest do
  use ExUnit.Case, async: true

  alias Flux.Vault
  alias Flux.Sinks.Secrets

  describe "encrypt_value/1 and decrypt_value/1" do
    test "round-trips strings, maps, and numbers" do
      for value <- ["secret-token", %{"key" => "val", "n" => 3}, 42, ["a", "b"]] do
        wrapper = Vault.encrypt_value(value)
        assert %{"encrypted" => true, "ciphertext" => ct} = wrapper
        assert is_binary(ct)
        assert Vault.decrypt_value(wrapper) == value
      end
    end

    test "ciphertext does not contain the plaintext" do
      %{"ciphertext" => ct} = Vault.encrypt_value("hunter2")
      refute ct =~ "hunter2"
    end

    test "encrypt_value is idempotent on an already-encrypted wrapper" do
      wrapper = Vault.encrypt_value("secret")
      assert Vault.encrypt_value(wrapper) == wrapper
    end

    test "decrypt_value passes plain values through unchanged" do
      assert Vault.decrypt_value("plain") == "plain"
      assert Vault.decrypt_value(%{"url" => "x"}) == %{"url" => "x"}
    end

    test "decrypting tampered ciphertext raises" do
      assert_raise Flux.Vault.DecryptError, fn ->
        Vault.decrypt_value(%{"encrypted" => true, "ciphertext" => "not-a-valid-token"})
      end
    end
  end

  describe "encrypt_map/2 and decrypt_map/1" do
    test "encrypts only secret paths, leaves other keys plaintext" do
      config = %{
        "url" => "https://example.com",
        "method" => "POST",
        "database_url" => "postgres://u:pw@h/db",
        "auth" => %{"type" => "bearer", "token" => "abc123"}
      }

      encrypted = Vault.encrypt_map(config, Secrets.paths())

      # Non-secret keys untouched.
      assert encrypted["url"] == "https://example.com"
      assert encrypted["method"] == "POST"

      # Secret keys wrapped.
      assert %{"encrypted" => true} = encrypted["database_url"]
      assert %{"encrypted" => true} = encrypted["auth"]["token"]
      # Non-secret nested key untouched.
      assert encrypted["auth"]["type"] == "bearer"
    end

    test "decrypt_map reverses encrypt_map (nested + top-level)" do
      config = %{
        "url" => "https://example.com",
        "database_url" => "postgres://u:pw@h/db",
        "auth" => %{"type" => "bearer", "token" => "abc123"}
      }

      assert config
             |> Vault.encrypt_map(Secrets.paths())
             |> Vault.decrypt_map(Secrets.paths()) == config
    end

    test "decrypt_map does NOT decrypt a wrapper relocated into a non-secret field" do
      # A stolen ciphertext wrapper pasted into a non-secret field (e.g. the
      # postgres `columns` map) must never be decrypted — otherwise the app is a
      # decryption oracle. Only the declared secret paths are decrypted.
      wrapper = Vault.encrypt_value("stolen-secret")

      config = %{
        "url" => "https://example.com",
        "columns" => %{"x" => wrapper}
      }

      result = Vault.decrypt_map(config, Secrets.paths())

      assert result["columns"]["x"] == wrapper
      refute result["columns"]["x"] == "stolen-secret"
    end

    test "encrypt_map skips missing paths and nil values" do
      config = %{"url" => "https://example.com"}
      assert Vault.encrypt_map(config, Secrets.paths()) == config
    end

    test "encrypt_map is idempotent" do
      config = %{"database_url" => "postgres://u:pw@h/db"}
      once = Vault.encrypt_map(config, Secrets.paths())
      twice = Vault.encrypt_map(once, Secrets.paths())
      assert once == twice
      assert Vault.decrypt_map(twice, Secrets.paths()) == config
    end

    test "decrypt_map passes a fully-plaintext (legacy) map through unchanged" do
      config = %{"database_url" => "postgres://u:pw@h/db", "url" => "x"}
      assert Vault.decrypt_map(config, Secrets.paths()) == config
    end
  end

  describe "encrypt_value/2 and decrypt_value/2 (AAD-bound)" do
    test "round-trips when the AAD matches" do
      for value <- ["totp-secret", %{"codes" => ["a", "b"]}, 7, ["x", "y"]] do
        wrapper = Vault.encrypt_value(value, "user:42")
        assert %{"encrypted" => true, "ciphertext" => ct} = wrapper
        assert is_binary(ct)
        assert Vault.decrypt_value(wrapper, "user:42") == value
      end
    end

    test "ciphertext does not contain the plaintext" do
      %{"ciphertext" => ct} = Vault.encrypt_value("hunter2", "user:42")
      refute ct =~ "hunter2"
    end

    test "decrypting with a different AAD raises (ciphertext bound to its record)" do
      wrapper = Vault.encrypt_value("totp-secret", "user:42")

      assert_raise Flux.Vault.DecryptError, fn ->
        Vault.decrypt_value(wrapper, "user:99")
      end
    end

    test "each encryption uses a fresh IV (same value + AAD yields different tokens)" do
      %{"ciphertext" => a} = Vault.encrypt_value("totp-secret", "user:42")
      %{"ciphertext" => b} = Vault.encrypt_value("totp-secret", "user:42")
      refute a == b
    end

    test "decrypting a tampered token raises" do
      assert_raise Flux.Vault.DecryptError, fn ->
        Vault.decrypt_value(
          %{"encrypted" => true, "ciphertext" => "not-a-valid-token"},
          "user:42"
        )
      end
    end

    test "decrypt_value/2 passes plain (non-wrapper) values through unchanged" do
      assert Vault.decrypt_value("plain", "user:42") == "plain"
      assert Vault.decrypt_value(nil, "user:42") == nil
    end
  end
end
