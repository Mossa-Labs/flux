defmodule Flux.Metering.Provider do
  @moduledoc """
  Contract for usage-metering / quota providers.

  Community ships `Flux.Metering.Providers.Community` (a no-op stub that reports
  zero usage and never enforces a quota — metering is a Pro feature). The
  commercial edition ships a provider backed by ETS counters + a daily Postgres
  rollup that reports real per-organization usage and enforces plan limits.

  Callers should use the `Flux.Metering` facade, which resolves the active
  provider via `Flux.Metering.Registry`.

  ## Usage map

  `get_usage/2` returns a map shaped like:

      %{
        period: %{start: ~D[..], end: ~D[..]} | nil,
        metrics: %{
          messages_ingested: non_neg_integer(),
          messages_processed: non_neg_integer(),
          sink_deliveries: non_neg_integer(),
          active_pipelines: non_neg_integer(),
          pipeline_hours: float()
        },
        quota: quota()
      }

  where `quota()` is the same shape returned by `quota_status/1`.
  """

  @type organization_id :: integer() | binary()
  @type usage :: %{
          period: %{start: Date.t(), end: Date.t()} | nil,
          metrics: %{
            messages_ingested: non_neg_integer(),
            messages_processed: non_neg_integer(),
            sink_deliveries: non_neg_integer(),
            active_pipelines: non_neg_integer(),
            pipeline_hours: float()
          },
          quota: quota()
        }
  @type quota :: %{
          unlimited: boolean(),
          limit: non_neg_integer() | nil,
          usage: non_neg_integer(),
          pct: float(),
          state: :ok | :warn | :over
        }

  @doc "Returns the current-period usage for an organization."
  @callback get_usage(organization_id(), opts :: keyword()) :: {:ok, usage()} | {:error, term()}

  @doc """
  Checks whether an organization is within its usage quota.

  Returns `:ok` when under the limit, or
  `{:error, {:quota_exceeded, retry_after_seconds}}` when over — callers on the
  ingestion path translate this into `429 Too Many Requests` + `Retry-After`.
  """
  @callback check_quota(organization_id()) ::
              :ok | {:error, {:quota_exceeded, non_neg_integer()}}

  @doc "Returns the quota status for an organization (for soft-warn UI/banners)."
  @callback quota_status(organization_id()) :: quota()
end
