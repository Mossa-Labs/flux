defmodule Flux.Pipelines.StepSecrets do
  @moduledoc """
  Credentials the pipeline builder keeps in a source node's `sourceConfig`,
  inside `pipeline.steps`, and how they are protected: encrypted at rest,
  masked in reads, dropped from exports.

  This module is the `Flux.Vault.SecretPaths` taxonomy for the `steps` column of
  `pipelines` and `pipeline_versions` (see `Flux.Vault.EncryptedConfig`). The
  same keys drive encryption and masking, so every value decrypted on load is
  also masked on the way out.

  A running source reads its credentials from its source record, never from
  pipeline steps, so nothing downstream of a read or an export needs them.
  Keys are the builder's IR names (see `assets/js/builder/types.ts`).
  """

  @behaviour Flux.Vault.SecretPaths

  @redacted "[REDACTED]"

  # `metadata` is the gRPC request headers, which can carry auth.
  @secret_keys ~w(password secretAccessKey sessionToken jwt credentials clientKey sslKeyfile
                  privateKey passphrase bearerToken metadata)

  @doc "The `sourceConfig` keys treated as credentials."
  @spec secret_keys() :: [String.t()]
  def secret_keys, do: @secret_keys

  @doc """
  `Flux.Vault.SecretPaths` callback: the path of every set credential in every
  source node, e.g. `["nodes", Access.at(0), "sourceConfig", "password"]`.

  Unset (`nil` / `""`) credentials are skipped, so blank builder fields stay
  blank on disk. Steps without a `"nodes"` list have no paths.
  """
  @impl Flux.Vault.SecretPaths
  def paths(%{"nodes" => nodes}) when is_list(nodes) do
    for {%{"sourceConfig" => config}, index} when is_map(config) <- Enum.with_index(nodes),
        key <- @secret_keys,
        Map.get(config, key) not in [nil, ""] do
      ["nodes", Access.at(index), "sourceConfig", key]
    end
  end

  def paths(_steps), do: []

  @doc """
  Masks set credentials in every source node, for read responses. Any
  encrypted wrapper left in a source node is masked too (defense-in-depth).
  """
  @spec redact(map() | nil) :: map() | nil
  def redact(steps),
    do: update_source_configs(steps, &(&1 |> mask() |> Flux.Vault.scrub_wrappers(@redacted)))

  @doc """
  Drops credentials from every source node, for exports. Masking would
  re-import as a literal `"[REDACTED]"`; dropping leaves the field empty, which
  the builder flags as missing until it's re-entered.
  """
  @spec strip(map() | nil) :: map() | nil
  def strip(steps), do: update_source_configs(steps, &Map.drop(&1, @secret_keys))

  defp update_source_configs(%{"nodes" => nodes} = steps, fun) when is_list(nodes) do
    nodes =
      Enum.map(nodes, fn
        %{"sourceConfig" => config} = node when is_map(config) ->
          Map.put(node, "sourceConfig", fun.(config))

        node ->
          node
      end)

    Map.put(steps, "nodes", nodes)
  end

  defp update_source_configs(steps, _fun), do: steps

  defp mask(config) do
    Enum.reduce(@secret_keys, config, fn key, acc ->
      case Map.get(acc, key) do
        empty when empty in [nil, ""] -> acc
        _secret -> Map.put(acc, key, @redacted)
      end
    end)
  end
end
