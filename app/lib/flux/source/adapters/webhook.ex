defmodule Flux.Source.Adapters.Webhook do
  @moduledoc """
  Community source adapter for inbound HTTP webhooks.

  Webhooks are a *passive* source: an HTTP request to
  `POST /api/webhooks/:source` (see `FluxWeb.API.WebhookController`) publishes
  the payload directly onto the internal queue, so there is no long-lived
  ingestion process (`ingestion_spec/2` returns `nil`).

  This adapter centralizes the `"webhooks.<source>"` queue-name convention so
  the controller and any pipeline wiring derive it from one place. The name is
  logical: `Flux.Queue` places it inside the organization of the API key that
  posted the webhook.
  """

  @behaviour Flux.Source.Adapter

  # One segment of a logical queue name (see `Flux.Queue.Naming`), short enough
  # that "webhooks.<source>" always fits.
  @source_format ~r/\A[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\z/

  @doc """
  Returns `true` if `source` can name a webhook source: it starts with a letter
  or digit, has only letters, digits, `_`, `.` and `-`, and is at most 128 bytes.
  """
  @spec valid_source?(term()) :: boolean()
  def valid_source?(source) when is_binary(source), do: Regex.match?(@source_format, source)
  def valid_source?(_source), do: false

  @impl Flux.Source.Adapter
  def queue_name(config) do
    "webhooks.#{source_name(config)}"
  end

  @impl Flux.Source.Adapter
  def ingestion_spec(_config, _opts), do: nil

  @impl Flux.Source.Adapter
  def validate_config(config) do
    case source_name(config) do
      name when is_binary(name) and name != "" ->
        if valid_source?(name),
          do: :ok,
          else:
            {:error,
             [
               "source must start with a letter or digit and contain only letters, digits, '_', '.' and '-'"
             ]}

      _ ->
        {:error, ["source is required"]}
    end
  end

  defp source_name(config) do
    Map.get(config, "source") || Map.get(config, "name")
  end
end
