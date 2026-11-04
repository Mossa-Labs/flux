defmodule Flux.Vault.EncryptedConfig do
  @moduledoc """
  Ecto type for a JSONB config column that transparently encrypts its secret
  fields at rest.

  Parameterized by a `Flux.Vault.SecretPaths` module that names where the
  secrets sit:

      field :config, Flux.Vault.EncryptedConfig, secrets: Flux.Sinks.Secrets, default: %{}

  Backed by `:map`. On `dump` (write), the values at the secret paths are
  encrypted via `Flux.Vault`; every other key is stored as plain JSONB. On
  `load` (read), the wrappers at those same paths are decrypted, so callers —
  schema structs, changesets, runtime adapters — always see plaintext.

  Encryption and decryption are both restricted to the paths the secrets module
  returns — the same paths its redaction layer masks — so no value is ever
  decrypted into a field that is later returned unredacted. A wrapper sitting
  anywhere else is left as ciphertext.

  Legacy plaintext rows are handled gracefully: `load` passes plaintext at a
  secret path through unchanged, and the next write encrypts it.

  `load` never raises. A secret that can't be decrypted with the current key
  loads as an undecryptable marker (see `Flux.Vault.decrypt_map/2`). Without
  that, one bad row would make every query that reads the row fail. `dump`
  writes the original ciphertext back unchanged.
  """

  use Ecto.ParameterizedType

  alias Flux.Vault

  @impl Ecto.ParameterizedType
  def init(opts) do
    case Keyword.fetch(opts, :secrets) do
      {:ok, secrets} when is_atom(secrets) ->
        %{secrets: secrets}

      _ ->
        raise ArgumentError,
              "#{inspect(__MODULE__)} requires a `secrets:` option naming a " <>
                "Flux.Vault.SecretPaths module"
    end
  end

  @impl Ecto.ParameterizedType
  def type(_params), do: :map

  @impl Ecto.ParameterizedType
  def cast(value, _params) when is_map(value), do: {:ok, value}
  def cast(nil, _params), do: {:ok, nil}
  def cast(_value, _params), do: :error

  @impl Ecto.ParameterizedType
  def load(value, _loader, %{secrets: secrets}) when is_map(value),
    do: {:ok, Vault.decrypt_map(value, secrets.paths(value))}

  def load(nil, _loader, _params), do: {:ok, nil}
  def load(_value, _loader, _params), do: :error

  @impl Ecto.ParameterizedType
  def dump(value, _dumper, %{secrets: secrets}) when is_map(value),
    do: {:ok, Vault.encrypt_map(value, secrets.paths(value))}

  def dump(nil, _dumper, _params), do: {:ok, nil}
  def dump(_value, _dumper, _params), do: :error
end
