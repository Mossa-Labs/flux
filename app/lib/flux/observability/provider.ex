defmodule Flux.Observability.Provider do
  @moduledoc """
  Contract for observability providers (MOS-472).

  Observability covers three metadata-only detectors keyed per source:

    * **Freshness SLO** — alerts when a source misses its expected arrival window.
    * **Volume baseline** — rolling per-source volume with statistical
      change-point detection; alerts on sudden drops or spikes.
    * **Schema drift** — observes the shape (field set + types) of *passing*
      messages and alerts on new/missing fields or type changes.

  Community ships `Flux.Observability.Providers.Community` — a no-op stub:
  `list_source_health/1` and `list_recent_drift/2` return `[]`, and every mutation
  returns `{:error, {:pro_required, :observability}}`. The commercial edition
  ships a provider backed by Postgres + a live ETS detector. Callers use the
  `Flux.Observability` facade, which resolves the active provider via
  `Flux.Observability.Registry`.

  The detection/observation side (telemetry handlers, change-point detection,
  fingerprint comparison) is intentionally *not* part of this contract — only the read/write
  surface the gated UI needs. Anomalies reach notification channels through the
  alerting feature's `freshness_slo`/`volume_anomaly`/`schema_drift` trigger types.

  ## Source-health map

  Providers return health as plain maps (the public side has no Ecto schema):

      %{
        source: String.t(),                  # e.g. "github" (from "webhooks.github")
        freshness: %{
          state: :ok | :warn | :breach | :unknown,
          last_seen_at: DateTime.t() | nil,
          expected_interval_seconds: pos_integer() | nil,
          age_seconds: non_neg_integer() | nil
        },
        volume: %{
          state: :ok | :spike | :drop | :unknown,
          current_rate: number(),            # messages in the last minute
          baseline_rate: number()            # rolling baseline
        },
        schema: %{
          state: :ok | :drift | :unknown,
          fingerprint: non_neg_integer() | nil,
          field_count: non_neg_integer() | nil,
          last_drift_at: DateTime.t() | nil
        }
      }

  An `slo()` is
  `%{source: String.t(), expected_interval_seconds: pos_integer(), warn_after_seconds: non_neg_integer(), enabled: boolean()}`.
  A `drift_event()` is
  `%{source: String.t(), kind: :added | :removed | :type_change, detail: map(), detected_at: DateTime.t()}`.
  """

  @type organization_id :: integer() | binary()
  @type source :: String.t()
  @type source_health :: map()
  @type slo :: map()
  @type drift_event :: map()

  @callback list_source_health(organization_id()) :: [source_health()]
  @callback get_slo(organization_id(), source()) :: {:ok, slo()} | {:error, :not_found}
  @callback upsert_slo(organization_id(), source(), attrs :: map()) ::
              {:ok, slo()} | {:error, term()}
  @callback delete_slo(organization_id(), source()) :: :ok | {:error, term()}
  @callback list_recent_drift(organization_id(), source()) :: [drift_event()]
end
