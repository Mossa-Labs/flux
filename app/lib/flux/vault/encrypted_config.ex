defmodule Flux.Vault.EncryptedConfig do
  @moduledoc """
  Ecto type for a sink `config` JSONB column that transparently encrypts secret
  fields at rest.

  Backed by `:map`. On `dump` (write), the secret values named by
  `Flux.Sinks.Secrets.paths/0` are encrypted via `Flux.Vault`; every other key
  (url, host, type, method, …) is stored as plain JSONB. On `load` (read), any
  encrypted wrapper anywhere in the map is decrypted, so callers — schema
  structs, changesets, runtime adapters — always see plaintext.

  Both directions are context-free: secrets are identified by key name (not sink
  type), so no per-adapter callback or changeset step is required. Simply set
  the schema field to this type.

  Encryption (`dump`) and decryption (`load`) are both restricted to the secret
  locations named by `Flux.Sinks.Secrets.paths/0` — the same paths the redaction
  layer masks — so no value is ever decrypted into a field that is subsequently
  returned unredacted.

  Legacy plaintext rows are handled gracefully: `load` passes plaintext at a
  secret path through unchanged, and the next write encrypts it.
  """

  use Ecto.Type

  alias Flux.Sinks.Secrets
  alias Flux.Vault

  @impl Ecto.Type
  def type, do: :map

  @impl Ecto.Type
  def cast(value) when is_map(value), do: {:ok, value}
  def cast(nil), do: {:ok, nil}
  def cast(_), do: :error

  @impl Ecto.Type
  def load(value) when is_map(value), do: {:ok, Vault.decrypt_map(value, Secrets.paths())}
  def load(nil), do: {:ok, nil}
  def load(_), do: :error

  @impl Ecto.Type
  def dump(value) when is_map(value), do: {:ok, Vault.encrypt_map(value, Secrets.paths())}
  def dump(nil), do: {:ok, nil}
  def dump(_), do: :error
end
