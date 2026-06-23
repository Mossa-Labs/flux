defmodule Flux.Observability do
  @moduledoc """
  Facade over the active `Flux.Observability.Provider`. The gated `/observability`
  LiveView (and the per-pipeline Observability tab) route all reads/writes through
  this module rather than calling a provider directly.

  Observability is a Pro feature (MOS-472): the Community build resolves to
  `Flux.Observability.Providers.Community`, a no-op stub. The commercial edition
  overlays a Postgres + ETS detector-backed provider via
  `Flux.Observability.Registry.set_active/1` at boot.

  See `Flux.Observability.Provider` for the source-health / SLO / drift map shapes.
  """

  alias Flux.Observability.Provider
  alias Flux.Observability.Registry

  @spec list_source_health(Provider.organization_id()) :: [Provider.source_health()]
  def list_source_health(organization_id),
    do: Registry.active().list_source_health(organization_id)

  @spec get_slo(Provider.organization_id(), Provider.source()) ::
          {:ok, Provider.slo()} | {:error, :not_found}
  def get_slo(organization_id, source), do: Registry.active().get_slo(organization_id, source)

  @spec upsert_slo(Provider.organization_id(), Provider.source(), map()) ::
          {:ok, Provider.slo()} | {:error, term()}
  def upsert_slo(organization_id, source, attrs),
    do: Registry.active().upsert_slo(organization_id, source, attrs)

  @spec delete_slo(Provider.organization_id(), Provider.source()) :: :ok | {:error, term()}
  def delete_slo(organization_id, source),
    do: Registry.active().delete_slo(organization_id, source)

  @spec list_recent_drift(Provider.organization_id(), Provider.source()) :: [
          Provider.drift_event()
        ]
  def list_recent_drift(organization_id, source),
    do: Registry.active().list_recent_drift(organization_id, source)
end
