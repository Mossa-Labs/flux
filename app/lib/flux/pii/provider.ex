defmodule Flux.PII.Provider do
  @moduledoc """
  Contract for PII redaction-metrics providers (MOS-480).

  PII redaction/classification is an Enterprise feature. The proprietary
  detectors and the aggregator that feeds this read surface live in the
  Enterprise edition; the public repo ships only the facade, this contract, and
  `Flux.PII.Providers.Community` — a no-op stub whose `stats/3` returns the empty
  shape so the gated dashboard renders an upgrade prompt instead of crashing.

  The **write/detection** side is intentionally *not* part of this contract.
  The `redact` step emits `[:flux, :pii, :redaction]` telemetry carrying **only
  per-type counts and field names, never values**; the Enterprise aggregator
  attaches a handler and maintains the rolling counters this contract reads.

  ## Stats map

  `stats/3` returns a plain map (the public side has no Ecto schema):

      %{
        window: %{
          from: DateTime.t(),
          to: DateTime.t(),
          bucket_seconds: pos_integer()
        },
        totals: %{
          messages_scanned: non_neg_integer(),
          messages_redacted: non_neg_integer(),
          redaction_rate: float(),        # messages_redacted / messages_scanned
          pii_instances: non_neg_integer()
        },
        by_type: %{optional(String.t()) => non_neg_integer()},   # "email" => 42
        by_field: %{
          optional(String.t()) => %{                             # "user.email" => …
            count: non_neg_integer(),
            by_type: %{optional(String.t()) => non_neg_integer()}
          }
        },
        timeline: [
          %{
            at: DateTime.t(),
            messages_redacted: non_neg_integer(),
            by_type: %{optional(String.t()) => non_neg_integer()}
          }
        ]
      }
  """

  @type organization_id :: integer() | binary()
  @type pipeline_id :: integer() | binary() | nil
  @type stats :: map()

  @doc """
  Redaction metrics for an organization, optionally scoped to one pipeline.

  `opts` may carry `:window_seconds` (default provider-defined) and
  `:bucket_seconds`. Must be total — return the empty stats shape rather than
  raising when there is no data.
  """
  @callback stats(organization_id(), pipeline_id(), opts :: keyword()) :: stats()
end
