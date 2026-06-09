defmodule Flux.Metering.Providers.Community do
  @moduledoc """
  Community no-op metering provider.

  Usage metering & quotas are a Pro feature. This stub reports zero usage and
  never enforces a quota, so the Community ingestion path is never throttled and
  the System Settings usage card / `GET /api/usage` show an upgrade prompt
  (gated by `Flux.License.has_feature?(:usage_metering)`) rather than this data.
  """

  @behaviour Flux.Metering.Provider

  @unlimited %{unlimited: true, limit: nil, usage: 0, pct: 0.0, state: :ok}

  @zero_usage %{
    period: nil,
    metrics: %{
      messages_ingested: 0,
      messages_processed: 0,
      sink_deliveries: 0,
      active_pipelines: 0,
      pipeline_hours: 0.0
    },
    quota: @unlimited
  }

  @impl true
  def get_usage(_organization_id, _opts), do: {:ok, @zero_usage}

  @impl true
  def check_quota(_organization_id), do: :ok

  @impl true
  def quota_status(_organization_id), do: @unlimited
end
