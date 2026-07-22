defmodule Flux.Sinks.Secrets do
  @moduledoc """
  Canonical taxonomy of secret-bearing keys in a sink `config` map.

  This is the single source of truth for *which* config values are sensitive
  (passwords, access keys, tokens, credentials). It is consumed by two
  independent concerns:

    * `Flux.Sinks.redact_config/1` — masks these values before a sink leaves
      the system (e.g. API responses).
    * `Flux.Vault.EncryptedConfig` — encrypts these values at rest and decrypts
      them transparently on read.

  Secrets are identified by *key name*, not by sink type, so the same taxonomy
  applies uniformly across every adapter (HTTP, Postgres/MySQL, S3, BigQuery,
  Kafka, Snowflake, Redis, Mongo, Slack). Top-level keys live directly on the
  config map; auth keys live nested under the `"auth"` map (HTTP-style auth).
  """

  # Top-level secret keys, across all sink types.
  @top_keys ~w(password private_key private_key_passphrase secret_access_key
               credentials database_url sasl_password ssl_keyfile uri
               webhook_url bot_token)

  # Secret keys nested under the HTTP-style `"auth"` map.
  @auth_keys ~w(token password username key)

  @doc "Top-level secret key names."
  @spec top_keys() :: [String.t()]
  def top_keys, do: @top_keys

  @doc "Secret key names nested under the `\"auth\"` map."
  @spec auth_keys() :: [String.t()]
  def auth_keys, do: @auth_keys

  @doc """
  All secret locations as a list of key paths (each path a list of string keys),
  e.g. `["database_url"]` and `["auth", "token"]`. Suitable for `get_in/2` and
  `put_in/3`.
  """
  @spec paths() :: [[String.t()]]
  def paths do
    Enum.map(@top_keys, &[&1]) ++ Enum.map(@auth_keys, &["auth", &1])
  end
end
