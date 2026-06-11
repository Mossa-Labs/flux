defmodule Flux.Alerts.Providers.Community do
  @moduledoc """
  Community no-op alerts provider.

  Alerting is a Pro feature. Listing returns empty; every mutation returns
  `{:error, {:pro_required, :alerting}}`. The gated `/system/alerts` LiveView
  short-circuits to an upgrade prompt (via `Flux.License.has_feature?(:alerting)`)
  before reaching these, but the stub keeps the facade total and crash-free.
  """

  @behaviour Flux.Alerts.Provider

  @pro_required {:error, {:pro_required, :alerting}}

  @impl true
  def list_rules(_organization_id), do: []

  @impl true
  def get_rule(_organization_id, _rule_id), do: {:error, :not_found}

  @impl true
  def create_rule(_organization_id, _attrs), do: @pro_required

  @impl true
  def update_rule(_organization_id, _rule_id, _attrs), do: @pro_required

  @impl true
  def delete_rule(_organization_id, _rule_id), do: @pro_required

  @impl true
  def toggle_rule(_organization_id, _rule_id, _enabled), do: @pro_required

  @impl true
  def list_history(_organization_id, _opts), do: []

  @impl true
  def test_channel(_channel), do: @pro_required
end
