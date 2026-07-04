defmodule Flux.Sink.Adapters.Stub do
  @moduledoc """
  Placeholder sink adapter registered against Pro-only sink types in
  Community builds. Every callback returns a structured
  `{:error, {:pro_required, feature_atom}}` tuple so the UI can render
  an upgrade prompt instead of crashing.

  EE builds replace the registration with the real adapter (e.g.
  `Flux.Sink.Adapters.S3`) at boot.
  """

  @behaviour Flux.Sink.Adapter

  @feature :pro_sink

  @impl Flux.Sink.Adapter
  def deliver(_data, config, _opts), do: pro_required(config)

  @impl Flux.Sink.Adapter
  def validate_config(config) do
    type = Map.get(config, "type", "unknown")
    {:error, ["#{type} sink requires Flux Pro — see https://fluxdata.tech/pricing"]}
  end

  @impl Flux.Sink.Adapter
  def test_connection(config), do: pro_required(config)

  defp pro_required(config) do
    type = Map.get(config, "type")
    {:error, {:pro_required, feature_for_type(type)}}
  end

  defp feature_for_type("s3"), do: :s3_sink
  defp feature_for_type("snowflake"), do: :snowflake_sink
  defp feature_for_type("bigquery"), do: :bigquery_sink
  defp feature_for_type("kafka"), do: :kafka_sink
  defp feature_for_type(_), do: @feature
end
