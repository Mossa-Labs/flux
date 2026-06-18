defmodule Flux.Alerts do
  @moduledoc """
  Facade over the active `Flux.Alerts.Provider`. The gated `/system/alerts`
  LiveView routes all alert-rule reads/writes through this module rather than
  calling a provider directly.

  Alerting is a Pro feature: the Community build resolves to
  `Flux.Alerts.Providers.Community`, a no-op stub. The commercial edition overlays
  a Postgres-backed provider (+ a minute-by-minute evaluation worker) via
  `Flux.Alerts.Registry.set_active/1` at boot.
  """

  alias Flux.Alerts.Provider
  alias Flux.Alerts.Registry

  @trigger_types [:anomaly, :failure_rate, :pipeline_stopped, :dlq_depth]
  @channel_types [:email, :webhook, :slack]

  @doc "Trigger types an alert rule can use."
  @spec trigger_types() :: [atom()]
  def trigger_types, do: @trigger_types

  @doc "Notification channel types a rule can dispatch to."
  @spec channel_types() :: [atom()]
  def channel_types, do: @channel_types

  @spec list_rules(Provider.organization_id()) :: [Provider.rule()]
  def list_rules(organization_id), do: Registry.active().list_rules(organization_id)

  @spec get_rule(Provider.organization_id(), Provider.rule_id()) ::
          {:ok, Provider.rule()} | {:error, :not_found}
  def get_rule(organization_id, rule_id), do: Registry.active().get_rule(organization_id, rule_id)

  @spec create_rule(Provider.organization_id(), map()) ::
          {:ok, Provider.rule()} | {:error, term()}
  def create_rule(organization_id, attrs),
    do: Registry.active().create_rule(organization_id, attrs)

  @spec update_rule(Provider.organization_id(), Provider.rule_id(), map()) ::
          {:ok, Provider.rule()} | {:error, term()}
  def update_rule(organization_id, rule_id, attrs),
    do: Registry.active().update_rule(organization_id, rule_id, attrs)

  @spec delete_rule(Provider.organization_id(), Provider.rule_id()) :: :ok | {:error, term()}
  def delete_rule(organization_id, rule_id),
    do: Registry.active().delete_rule(organization_id, rule_id)

  @spec toggle_rule(Provider.organization_id(), Provider.rule_id(), boolean()) ::
          {:ok, Provider.rule()} | {:error, term()}
  def toggle_rule(organization_id, rule_id, enabled),
    do: Registry.active().toggle_rule(organization_id, rule_id, enabled)

  @spec list_history(Provider.organization_id(), keyword()) :: [Provider.history_entry()]
  def list_history(organization_id, opts \\ []),
    do: Registry.active().list_history(organization_id, opts)

  @spec test_channel(Provider.channel()) :: :ok | {:error, term()}
  def test_channel(channel), do: Registry.active().test_channel(channel)

  @doc """
  Records a rule-less event (e.g. a bulk DLQ replay) in alert history. No-op in
  Community builds.
  """
  @spec record_event(Provider.organization_id(), map()) :: :ok
  def record_event(organization_id, event),
    do: Registry.active().record_event(organization_id, event)
end
