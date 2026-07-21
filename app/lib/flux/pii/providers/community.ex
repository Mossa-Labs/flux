defmodule Flux.PII.Providers.Community do
  @moduledoc """
  Community no-op PII metrics provider (MOS-480).

  PII redaction/classification is an Enterprise feature. `stats/3` returns the
  empty stats shape (zeroed totals, empty breakdowns) so the gated `/redaction`
  dashboard renders an upgrade prompt — via `Flux.License.has_feature?(:pii_redaction)`
  — rather than crashing. The Enterprise edition overlays `Flux.PII.Aggregator`.
  """

  @behaviour Flux.PII.Provider

  @impl true
  def stats(_organization_id, _pipeline_id, opts) do
    now = DateTime.utc_now()
    window_seconds = Keyword.get(opts, :window_seconds, 3600)
    bucket_seconds = Keyword.get(opts, :bucket_seconds, 300)

    %{
      window: %{
        from: DateTime.add(now, -window_seconds, :second),
        to: now,
        bucket_seconds: bucket_seconds
      },
      totals: %{
        messages_scanned: 0,
        messages_redacted: 0,
        redaction_rate: 0.0,
        pii_instances: 0
      },
      by_type: %{},
      by_field: %{},
      timeline: []
    }
  end
end
