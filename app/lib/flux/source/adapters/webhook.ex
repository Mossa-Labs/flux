defmodule Flux.Source.Adapters.Webhook do
  @moduledoc """
  Community source adapter for inbound HTTP webhooks.

  Webhooks are a *passive* source: an HTTP request to
  `POST /api/webhooks/:source` (see `FluxWeb.API.WebhookController`) publishes
  the payload directly onto the internal queue, so there is no long-lived
  ingestion process (`ingestion_spec/2` returns `nil`).

  This adapter centralizes the `"webhooks.<source>"` queue-name convention so
  the controller and any pipeline wiring derive it from one place.
  """

  @behaviour Flux.Source.Adapter

  @impl Flux.Source.Adapter
  def queue_name(config) do
    "webhooks.#{source_name(config)}"
  end

  @impl Flux.Source.Adapter
  def ingestion_spec(_config, _opts), do: nil

  @impl Flux.Source.Adapter
  def validate_config(config) do
    case source_name(config) do
      name when is_binary(name) and name != "" -> :ok
      _ -> {:error, ["source is required"]}
    end
  end

  defp source_name(config) do
    Map.get(config, "source") || Map.get(config, "name")
  end
end
