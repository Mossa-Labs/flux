defmodule Flux.Source.Adapters.Poll do
  @moduledoc """
  Community source adapter for scheduled HTTP polling.

  Polling is a *passive* source driven by Oban: `Flux.Workers.Poller` fetches a
  URL on a schedule and publishes the result onto the internal queue, so there
  is no long-lived ingestion process (`ingestion_spec/2` returns `nil`).

  This adapter centralizes the `"polling.<source_id>"` queue-name convention.

  Note: *recurring* (cron) scheduling is the `:cron_polling` Pro feature — the
  `Oban.Plugins.Cron` plugin is only wired up in licensed builds. One-off polls
  enqueued directly still run on Community, hence this adapter is ungated.
  """

  @behaviour Flux.Source.Adapter

  @impl Flux.Source.Adapter
  def queue_name(config) do
    "polling.#{source_id(config)}"
  end

  @impl Flux.Source.Adapter
  def ingestion_spec(_config, _opts), do: nil

  @impl Flux.Source.Adapter
  def validate_config(config) do
    errors =
      []
      |> require_field(source_id(config), "source_id is required")
      |> validate_url(Map.get(config, "url"))

    if errors == [], do: :ok, else: {:error, Enum.reverse(errors)}
  end

  defp source_id(config) do
    Map.get(config, "source_id") || Map.get(config, "name")
  end

  defp require_field(errors, value, _msg) when is_binary(value) and value != "", do: errors
  defp require_field(errors, _value, msg), do: [msg | errors]

  # URL is optional (the skeleton poller returns placeholder data when absent),
  # but if present it must be a valid http(s) URL.
  defp validate_url(errors, nil), do: errors
  defp validate_url(errors, ""), do: errors

  defp validate_url(errors, url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host}}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        errors

      _ ->
        ["url must be a valid http(s) URL" | errors]
    end
  end

  defp validate_url(errors, _url), do: ["url must be a valid http(s) URL" | errors]
end
