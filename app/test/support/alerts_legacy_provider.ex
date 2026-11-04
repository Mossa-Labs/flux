defmodule Flux.AlertsLegacyProvider do
  @moduledoc """
  A `Flux.Alerts.Provider` that predates the optional `test_rule/2` callback,
  for testing the facade's fallback. It delegates everything else to
  `Flux.AlertsTestProvider`.
  """

  @behaviour Flux.Alerts.Provider

  alias Flux.AlertsTestProvider, as: P

  @impl true
  defdelegate list_rules(org_id), to: P
  @impl true
  defdelegate get_rule(org_id, rule_id), to: P
  @impl true
  defdelegate create_rule(org_id, attrs), to: P
  @impl true
  defdelegate update_rule(org_id, rule_id, attrs), to: P
  @impl true
  defdelegate delete_rule(org_id, rule_id), to: P
  @impl true
  defdelegate toggle_rule(org_id, rule_id, enabled), to: P
  @impl true
  defdelegate list_history(org_id, opts), to: P
  @impl true
  defdelegate test_channel(channel), to: P
  @impl true
  defdelegate record_event(org_id, event), to: P
end
