defmodule Flux.Source.GRPC do
  @moduledoc """
  The gRPC source's queue-naming convention, kept in one place so the pipeline
  builder, the Community stub and the adapter that serves the source all derive
  the same internal queue.

  A gRPC source publishes to `grpc.<channel>`, with the channel slugged
  (lowercase; anything outside `a-z0-9_-` becomes `-`). Server mode requires a
  channel; a client-mode source without one derives it from its RPC method path,
  so `/telemetry.v1.Telemetry/StreamReadings` feeds
  `grpc.telemetry-v1-telemetry-streamreadings`.
  """

  @doc "The internal queue a gRPC source config publishes to."
  @spec queue_name(map()) :: String.t()
  def queue_name(config) do
    channel =
      case {present(config["channel"]), present(config["mode"]) || "server"} do
        {nil, "client"} -> slug(present(config["method"]) || "stream")
        {nil, _server} -> "ingest"
        {channel, _mode} -> slug(channel)
      end

    "grpc." <> channel
  end

  defp present(value) when is_binary(value) and value != "", do: value
  defp present(_value), do: nil

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "ingest"
      slug -> slug
    end
  end
end
