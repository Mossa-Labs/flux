defmodule Flux.Source.Adapters.Stub do
  @moduledoc """
  Placeholder source adapter registered against Pro-only source types in
  Community builds. Config validation returns a structured
  `{:error, {:pro_required, feature_atom}}`-style message so the UI can render
  an upgrade prompt instead of crashing, and `ingestion_spec/2` starts nothing.

  EE builds replace the registration with the real adapter (e.g.
  `Flux.Source.Adapters.Kafka`) at boot.
  """

  @behaviour Flux.Source.Adapter

  @feature :pro_source

  @impl Flux.Source.Adapter
  def queue_name(config) do
    # Deterministic name so a stored config still round-trips; nothing consumes
    # it in Community because the source never ingests.
    name = Map.get(config, "name") || Map.get(config, "source") || "stub"
    type = Map.get(config, "type", "source")
    "#{type}.#{name}"
  end

  @impl Flux.Source.Adapter
  def ingestion_spec(_config, _opts), do: nil

  @impl Flux.Source.Adapter
  def validate_config(config) do
    type = Map.get(config, "type", "unknown")
    {:error, ["#{type} source requires Flux Pro — see https://fluxdata.tech/pricing"]}
  end

  @impl Flux.Source.Adapter
  def test_connection(config), do: {:error, {:pro_required, feature_for_type(config["type"])}}

  @doc """
  Resolves a source type to the license feature gating it. Public so callers
  (e.g. LiveViews) can render the matching upgrade prompt.
  """
  @spec feature_for_type(String.t() | nil) :: atom()
  def feature_for_type("kafka"), do: :kafka_source
  def feature_for_type("mqtt"), do: :mqtt_source
  def feature_for_type("sqs"), do: :sqs_source
  def feature_for_type("kinesis"), do: :kinesis_source
  def feature_for_type("pubsub"), do: :pubsub_source
  def feature_for_type(_), do: @feature
end
