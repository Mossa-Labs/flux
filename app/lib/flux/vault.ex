defmodule Flux.Vault do
  @moduledoc """
  Application-layer encryption for secrets at rest.

  Wraps `Plug.Crypto.MessageEncryptor` (AES-GCM, authenticated) to encrypt
  individual values, and provides map-walking helpers used by
  `Flux.Vault.EncryptedConfig` to transparently encrypt/decrypt the sensitive
  fields of a sink `config` JSONB column.

  ## Key management

  The encryption key is derived (via PBKDF2, `Plug.Crypto.KeyGenerator`) from,
  in order of precedence:

    1. `config :flux, Flux.Vault, key: "..."` — a dedicated key, typically from
       the `FLUX_VAULT_KEY` environment variable.
    2. the endpoint `:secret_key_base`, so existing deployments encrypt at rest
       with no additional configuration.

  Derivation uses fixed, versioned salts, so a given base key always yields the
  same encryption/signing keys. To rotate keys, set `FLUX_VAULT_KEY`, re-encrypt
  existing rows (`mix flux.vault.encrypt_sinks`), and keep the previous base key
  available until every row has been re-written.

  ## Encrypted value shape

  A secret value is stored as a self-describing JSONB object:

      %{"encrypted" => true, "ciphertext" => "<url-safe base64 token>"}

  Encryption and decryption are both driven by the same list of secret paths
  (`Flux.Sinks.Secrets.paths/0`) — see `encrypt_map/2` and `decrypt_map/2`. We do
  **not** decrypt by blindly walking the map for wrappers: decryption is
  restricted to the exact locations that the redaction layer also masks, so a
  wrapper relocated into a non-secret field is never decrypted and can never be
  read back as plaintext.
  """

  @wrapper_key "encrypted"
  @ciphertext_key "ciphertext"

  @aes_salt "flux.vault.aes256.v1"
  @sign_salt "flux.vault.sign.v1"

  @doc """
  Encrypts a single JSON-serializable value, returning the wrapper map.

  Values already wrapped are returned unchanged, making this idempotent.
  """
  @spec encrypt_value(term()) :: map()
  def encrypt_value(%{@wrapper_key => true} = wrapper), do: wrapper

  def encrypt_value(value) do
    {aes, sign} = keys()
    token = Plug.Crypto.MessageEncryptor.encrypt(Jason.encode!(value), aes, sign)
    %{@wrapper_key => true, @ciphertext_key => token}
  end

  @doc """
  Decrypts a wrapper produced by `encrypt_value/1`, returning the original value.

  Non-wrapper values are returned unchanged. Raises `Flux.Vault.DecryptError`
  if a wrapper's ciphertext cannot be decrypted (wrong key / tampering).
  """
  @spec decrypt_value(term()) :: term()
  def decrypt_value(%{@wrapper_key => true, @ciphertext_key => token}) when is_binary(token) do
    {aes, sign} = keys()

    case Plug.Crypto.MessageEncryptor.decrypt(token, aes, sign) do
      {:ok, json} -> Jason.decode!(json)
      :error -> raise Flux.Vault.DecryptError
    end
  end

  def decrypt_value(value), do: value

  @doc """
  Encrypts the values at the given `paths` within `config`.

  Each path is a list of string keys (see `Flux.Sinks.Secrets.paths/0`). Paths
  whose parent is missing or whose value is `nil` are skipped. Already-encrypted
  values are left as-is (idempotent).
  """
  @spec encrypt_map(map(), [[String.t()]]) :: map()
  def encrypt_map(config, paths) when is_map(config) do
    Enum.reduce(paths, config, fn path, acc ->
      case get_in(acc, path) do
        nil -> acc
        value -> put_in_path(acc, path, encrypt_value(value))
      end
    end)
  end

  def encrypt_map(config, _paths), do: config

  @doc """
  Decrypts the encrypted values at the given `paths` within `config`.

  Symmetric with `encrypt_map/2`: decryption happens **only** at the known secret
  locations, never as a blind walk of the whole map. This is a security
  invariant — the caller redacts exactly these same paths before returning a
  config (see `Flux.Sinks.redact_config/1`), so any value we decrypt is also a
  value that is masked on the way out. A wrapper an attacker relocates into a
  non-secret field is therefore never decrypted, and cannot be turned into a
  decryption oracle.

  Legacy plaintext values sitting at a secret path pass through unchanged.
  """
  @spec decrypt_map(map(), [[String.t()]]) :: map()
  def decrypt_map(config, paths) when is_map(config) do
    Enum.reduce(paths, config, fn path, acc ->
      case get_in(acc, path) do
        %{@wrapper_key => true, @ciphertext_key => _} = wrapper ->
          put_in_path(acc, path, decrypt_value(wrapper))

        _ ->
          acc
      end
    end)
  end

  def decrypt_map(config, _paths), do: config

  # `put_in/3` requires every parent to exist; `get_in/2` already told us the
  # value is present, so the parents do too.
  defp put_in_path(config, path, value), do: put_in(config, path, value)

  # Derives {aes_key, sign_key} from the configured base key or secret_key_base.
  defp keys do
    base = base_key()
    aes = Plug.Crypto.KeyGenerator.generate(base, @aes_salt, length: 32)
    sign = Plug.Crypto.KeyGenerator.generate(base, @sign_salt, length: 32)
    {aes, sign}
  end

  defp base_key do
    case Application.get_env(:flux, __MODULE__, [])[:key] do
      key when is_binary(key) and byte_size(key) >= 16 ->
        key

      _ ->
        secret_key_base() ||
          raise """
          Flux.Vault has no encryption key. Set `FLUX_VAULT_KEY` (config
          :flux, Flux.Vault, key: ...) or ensure the endpoint :secret_key_base
          is configured.
          """
    end
  end

  defp secret_key_base do
    :flux
    |> Application.get_env(FluxWeb.Endpoint, [])
    |> Keyword.get(:secret_key_base)
  end
end
