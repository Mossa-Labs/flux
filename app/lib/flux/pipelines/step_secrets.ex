defmodule Flux.Pipelines.StepSecrets do
  @moduledoc """
  Credentials the pipeline builder keeps in a source node's `sourceConfig`,
  inside `pipeline.steps`, and how they leave the system: masked in reads,
  dropped from exports.

  A running source reads its credentials from its source record, never from
  pipeline steps, so nothing downstream of a read or an export needs them.
  Keys are the builder's IR names (see `assets/js/builder/types.ts`).
  """

  @redacted "[REDACTED]"

  @secret_keys ~w(password secretAccessKey sessionToken jwt credentials clientKey sslKeyfile
                  privateKey passphrase bearerToken)

  @doc "The `sourceConfig` keys treated as credentials."
  @spec secret_keys() :: [String.t()]
  def secret_keys, do: @secret_keys

  @doc "Masks set credentials in every source node, for read responses."
  @spec redact(map() | nil) :: map() | nil
  def redact(steps), do: update_source_configs(steps, &mask/1)

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
