defmodule Flux.Observability.Providers.Community do
  @moduledoc """
  Community no-op observability provider.

  Observability (freshness SLO / volume baseline / schema drift) is a Pro feature.
  Listing returns empty; every mutation returns
  `{:error, {:pro_required, :observability}}`. The gated `/observability` LiveView
  short-circuits to an upgrade prompt (via
  `Flux.License.has_feature?(:observability)`) before reaching these, but the stub
  keeps the facade total and crash-free.
  """

  @behaviour Flux.Observability.Provider

  @pro_required {:error, {:pro_required, :observability}}

  @impl true
  def list_source_health(_organization_id), do: []

  @impl true
  def get_slo(_organization_id, _source), do: {:error, :not_found}

  @impl true
  def upsert_slo(_organization_id, _source, _attrs), do: @pro_required

  @impl true
  def delete_slo(_organization_id, _source), do: @pro_required

  @impl true
  def list_recent_drift(_organization_id, _source), do: []
end
