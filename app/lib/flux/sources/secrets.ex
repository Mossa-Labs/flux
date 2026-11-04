defmodule Flux.Sources.Secrets do
  @moduledoc """
  Canonical taxonomy of secret-bearing keys in a source `config` map.

  The single source of truth for *which* source config values are sensitive.
  It is consumed by two independent concerns, which must never disagree:

    * `Flux.Sources.redact_config/1` — masks these values before a source
      leaves the system.
    * `Flux.Vault.EncryptedConfig` — encrypts these values at rest and decrypts
      them transparently on read (`sources.config`).

  Secrets are identified by *key name*, not by source type:

    * `password` — SFTP, MQTT, RabbitMQ.
    * `sasl_password` — Kafka SASL.
    * `private_key`, `passphrase`, `certificate` — SFTP key-pair auth.
    * `client_key`, `bearer_token` — gRPC and RabbitMQ mTLS keys / gRPC tokens.
    * `secret_access_key`, `session_token` — AWS (SQS, Kinesis).
    * `credentials` — a Google service-account JSON (Pub/Sub).
    * `jwt` — MQTT JWT auth.
    * `metadata` — gRPC request headers, which can carry auth; the whole value
      is treated as secret whether it is a map or a JSON string.

  Top-level keys live directly on the config map; auth keys live nested under
  an `"auth"` map (HTTP-style auth), matching the sink taxonomy.
  """

  @behaviour Flux.Vault.SecretPaths

  # Top-level secret keys, across all source types.
  @top_keys ~w(password sasl_password private_key passphrase certificate bearer_token client_key
               secret_access_key session_token credentials jwt metadata)

  # Secret keys nested under an HTTP-style `"auth"` map.
  @auth_keys ~w(token password username key)

  @doc "Top-level secret key names."
  @spec top_keys() :: [String.t()]
  def top_keys, do: @top_keys

  @doc "Secret key names nested under the `\"auth\"` map."
  @spec auth_keys() :: [String.t()]
  def auth_keys, do: @auth_keys

  @doc """
  All secret locations as a list of key paths, e.g. `["password"]` and
  `["auth", "token"]`. Suitable for `get_in/2` and `put_in/3`.
  """
  @spec paths() :: [[String.t()]]
  def paths do
    Enum.map(@top_keys, &[&1]) ++ Enum.map(@auth_keys, &["auth", &1])
  end

  @doc """
  `Flux.Vault.SecretPaths` callback: the secret paths are the same for every
  source config, so this ignores `config` and returns `paths/0`.
  """
  @impl Flux.Vault.SecretPaths
  def paths(_config), do: paths()
end
