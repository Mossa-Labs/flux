defmodule Flux.Metering do
  @moduledoc """
  Facade over the active `Flux.Metering.Provider`. All UI, API, and
  ingestion-path code should route through this module rather than calling a
  provider directly.

  Metering is a Pro feature: the Community build resolves to
  `Flux.Metering.Providers.Community`, a no-op stub that reports zero usage and
  never enforces a quota. The commercial edition overlays a real provider via
  `Flux.Metering.Registry.set_active/1` at boot.
  """

  alias Flux.Metering.Provider
  alias Flux.Metering.Registry

  @metrics [
    :messages_ingested,
    :messages_processed,
    :sink_deliveries,
    :active_pipelines,
    :pipeline_hours
  ]

  @doc "Canonical metric keys tracked per organization."
  @spec metrics() :: [atom()]
  def metrics, do: @metrics

  @spec get_usage(Provider.organization_id(), keyword()) ::
          {:ok, Provider.usage()} | {:error, term()}
  def get_usage(organization_id, opts \\ []),
    do: Registry.active().get_usage(organization_id, opts)

  @spec check_quota(Provider.organization_id()) ::
          :ok | {:error, {:quota_exceeded, non_neg_integer()}}
  def check_quota(organization_id), do: Registry.active().check_quota(organization_id)

  @spec quota_status(Provider.organization_id()) :: Provider.quota()
  def quota_status(organization_id), do: Registry.active().quota_status(organization_id)
end
