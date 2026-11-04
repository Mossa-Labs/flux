defmodule Flux.Vault do
  @moduledoc """
  Application-layer encryption for secrets at rest.

  Wraps `Plug.Crypto.MessageEncryptor` (AES-GCM, authenticated) to encrypt
  individual values, and provides map-walking helpers used by
  `Flux.Vault.EncryptedConfig` to transparently encrypt/decrypt the sensitive
  fields of a JSONB config column: `sinks.config`, `sources.config`, and the
  builder's source credentials in `pipelines.steps` / `pipeline_versions.steps`.

  ## Key management

  The encryption key is derived (via PBKDF2, `Plug.Crypto.KeyGenerator`) from,
  in order of precedence:

    1. `config :flux, Flux.Vault, key: "..."` — a dedicated key, typically from
       the `FLUX_VAULT_KEY` environment variable.
    2. the endpoint `:secret_key_base`, so existing deployments encrypt at rest
       with no additional configuration.

  Derivation uses fixed, versioned salts, so a given base key always yields the
  same encryption/signing keys. To rotate keys, set `FLUX_VAULT_KEY`, re-encrypt
  existing rows (`mix flux.vault.encrypt_sinks` for sinks; sources and pipelines
  are re-encrypted on their next save), and keep the previous base key available
  until every row has been re-written.

  ## Encrypted value shape

  A secret value is stored as a self-describing JSONB object:

      %{"encrypted" => true, "ciphertext" => "<url-safe base64 token>"}

  Encryption and decryption are both driven by the same list of secret paths
  (a `Flux.Vault.SecretPaths` module, e.g. `Flux.Sinks.Secrets`) — see
  `encrypt_map/2` and `decrypt_map/2`. We do
  **not** decrypt by blindly walking the map for wrappers: decryption is
  restricted to the exact locations that the redaction layer also masks, so a
  wrapper relocated into a non-secret field is never decrypted and can never be
  read back as plaintext.
  """

  @wrapper_key "encrypted"
  @ciphertext_key "ciphertext"
  @undecryptable_key "undecryptable"

  @aes_salt "flux.vault.aes256.v1"
  @sign_salt "flux.vault.sign.v1"
  @aead_salt "flux.vault.aead256.v1"

  @doc """
  Encrypts a single JSON-serializable value, returning the wrapper map.

  Values already wrapped are returned unchanged, making this idempotent. The
  one exception is an undecryptable marker (see `decrypt_map/2`): its
  `"undecryptable"` flag is dropped, so the stored row keeps the original
  ciphertext and never stores a flag that depends on which key is loaded.
  """
  @spec encrypt_value(term()) :: map()
  def encrypt_value(%{@wrapper_key => true} = wrapper),
    do: Map.delete(wrapper, @undecryptable_key)

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
  Encrypts `value`, binding the ciphertext to `aad` (additional authenticated data).

  Unlike `encrypt_value/1`, the token produced here can only be decrypted by supplying
  the exact same `aad` to `decrypt_value/2`. Pass a stable record identifier (e.g. a
  user id) so a stolen ciphertext cannot be lifted out of one row and replayed against
  another — the GCM tag covers the AAD, so a mismatch fails authentication.

  Uses AES-256-GCM directly (`:crypto`) because `Plug.Crypto.MessageEncryptor` exposes
  no AAD channel. The token packs `iv <> tag <> ciphertext`, base64url-encoded, into the
  same self-describing wrapper shape. The AAD itself is **not** stored — the caller must
  supply it again at decrypt time.
  """
  @spec encrypt_value(term(), binary()) :: map()
  def encrypt_value(value, aad) when is_binary(aad) do
    key = aead_key()
    iv = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, Jason.encode!(value), aad, true)

    token = Base.url_encode64(iv <> tag <> ciphertext, padding: false)
    %{@wrapper_key => true, @ciphertext_key => token}
  end

  @doc """
  Decrypts an AAD-bound wrapper produced by `encrypt_value/2`.

  The `aad` must exactly match the value passed at encryption time. Non-wrapper values
  pass through unchanged. Raises `Flux.Vault.DecryptError` on a wrong key, a tampered
  token, or an AAD mismatch (the three are indistinguishable — a GCM authentication
  failure — by design).
  """
  @spec decrypt_value(term(), binary()) :: term()
  def decrypt_value(%{@wrapper_key => true, @ciphertext_key => token}, aad)
      when is_binary(token) and is_binary(aad) do
    key = aead_key()

    with {:ok, <<iv::binary-size(12), tag::binary-size(16), ciphertext::binary>>} <-
           Base.url_decode64(token, padding: false),
         plaintext when is_binary(plaintext) <-
           :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, aad, tag, false) do
      Jason.decode!(plaintext)
    else
      _ -> raise Flux.Vault.DecryptError
    end
  end

  def decrypt_value(value, _aad), do: value

  @doc """
  Encrypts the values at the given `paths` within `config`.

  Each path is a list of string keys or `Access.at/1` steps (see
  `Flux.Vault.SecretPaths`). Paths whose parent is missing or whose value is
  `nil` are skipped. Already-encrypted values are left as-is (idempotent).
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

  ## Undecryptable values

  This function never raises. A wrapper whose ciphertext cannot be decrypted
  (a rotated or wrong key, a backup restored next to a different key, or
  tampering), or a damaged wrapper with a missing or non-string `ciphertext`,
  is replaced by an *undecryptable marker*: the same wrapper with
  `"undecryptable" => true` added. One bad secret therefore can't stop the
  whole row from loading, and with it every list query that includes the row.

  The marker keeps the original ciphertext. `encrypt_value/1` strips the flag,
  so writing the row back stores the untouched ciphertext and loses nothing.
  If the right key is restored later, the secret decrypts again. Callers detect
  the marker with `undecryptable_paths/2` and `undecryptable?/1`. Redaction
  masks it like any other wrapper (`scrub_wrappers/2`).
  """
  @spec decrypt_map(map(), [[String.t()]]) :: map()
  def decrypt_map(config, paths) when is_map(config) do
    Enum.reduce(paths, config, fn path, acc ->
      case get_in(acc, path) do
        %{@wrapper_key => true} = wrapper ->
          put_in_path(acc, path, decrypt_or_mark(wrapper))

        _ ->
          acc
      end
    end)
  end

  def decrypt_map(config, _paths), do: config

  @doc """
  Returns `true` if `value` is an undecryptable marker left by `decrypt_map/2`.
  """
  @spec undecryptable?(term()) :: boolean()
  def undecryptable?(%{@wrapper_key => true, @undecryptable_key => true}), do: true
  def undecryptable?(_value), do: false

  @doc """
  Returns the subset of `paths` whose value in `config` is an undecryptable
  marker (see `decrypt_map/2`).
  """
  @spec undecryptable_paths(map(), [list()]) :: [list()]
  def undecryptable_paths(config, paths) when is_map(config),
    do: Enum.filter(paths, &undecryptable?(get_in(config, &1)))

  def undecryptable_paths(_config, _paths), do: []

  defp decrypt_or_mark(%{@ciphertext_key => token} = wrapper) when is_binary(token) do
    {aes, sign} = keys()

    case Plug.Crypto.MessageEncryptor.decrypt(token, aes, sign) do
      {:ok, json} -> Jason.decode!(json)
      :error -> mark_undecryptable(wrapper)
    end
  end

  defp decrypt_or_mark(wrapper), do: mark_undecryptable(wrapper)

  defp mark_undecryptable(wrapper) do
    wrapper
    |> Map.take([@wrapper_key, @ciphertext_key])
    |> Map.put(@undecryptable_key, true)
  end

  @doc """
  Replaces every encrypted wrapper anywhere in `value` with `replacement`.

  Defense-in-depth for the redaction layers: a wrapper that survives to the
  output — e.g. a ciphertext blob planted in a non-secret field, which
  `decrypt_map/2` deliberately leaves alone — is masked instead of echoed back.
  """
  @spec scrub_wrappers(term(), term()) :: term()
  def scrub_wrappers(%{@wrapper_key => true}, replacement), do: replacement

  def scrub_wrappers(map, replacement) when is_map(map),
    do: Map.new(map, fn {k, v} -> {k, scrub_wrappers(v, replacement)} end)

  def scrub_wrappers(list, replacement) when is_list(list),
    do: Enum.map(list, &scrub_wrappers(&1, replacement))

  def scrub_wrappers(value, _replacement), do: value

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

  # Derives the AES-256-GCM key for AAD-bound encryption (encrypt_value/2). A distinct
  # salt keeps it independent of the MessageEncryptor keys used for sink secrets.
  defp aead_key do
    Plug.Crypto.KeyGenerator.generate(base_key(), @aead_salt, length: 32)
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
