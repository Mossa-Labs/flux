defmodule Flux.Alerts.Provider do
  @moduledoc """
  Contract for alert-rule providers (MOS-452).

  Community ships `Flux.Alerts.Providers.Community` — a no-op stub: listing
  returns `[]` and every mutation returns `{:error, {:pro_required, :alerting}}`
  (alerting is a Pro feature). The commercial edition ships a provider backed by
  Postgres (`alert_rules` / `alert_history`) plus an evaluation engine that fires
  notifications.

  Callers should use the `Flux.Alerts` facade, which resolves the active provider
  via `Flux.Alerts.Registry`. The evaluation/fire side (running every minute as a
  Pro Oban worker) is intentionally *not* part of this contract — only the
  read/write surface the gated UI needs.

  ## Rule map

  Providers return rules as plain maps (the public side has no Ecto schema):

      %{
        id: term(),
        name: String.t(),
        trigger_type: :anomaly | :failure_rate | :pipeline_stopped | :dlq_depth
                       | :freshness_slo | :volume_anomaly | :schema_drift,
        trigger_config: map(),         # e.g. %{"threshold" => 3.0}
        channels: [channel()],         # array of %{"type" => ..., "config" => ...}
        enabled: boolean(),
        cooldown_minutes: non_neg_integer(),
        last_fired_at: DateTime.t() | nil,
        inserted_at: DateTime.t(),
        updated_at: DateTime.t()
      }

  A `channel()` is `%{"type" => "email" | "webhook" | "slack", "config" => map()}`.
  A `history_entry()` is
  `%{id: ..., trigger_type: ..., trigger_data: map(), channels_sent: map(), inserted_at: DateTime.t()}`.
  """

  @type organization_id :: integer() | binary()
  @type rule_id :: integer() | binary()
  @type rule :: map()
  @type history_entry :: map()
  @type channel :: map()

  @callback list_rules(organization_id()) :: [rule()]
  @callback get_rule(organization_id(), rule_id()) :: {:ok, rule()} | {:error, :not_found}
  @callback create_rule(organization_id(), attrs :: map()) :: {:ok, rule()} | {:error, term()}
  @callback update_rule(organization_id(), rule_id(), attrs :: map()) ::
              {:ok, rule()} | {:error, term()}
  @callback delete_rule(organization_id(), rule_id()) :: :ok | {:error, term()}
  @callback toggle_rule(organization_id(), rule_id(), enabled :: boolean()) ::
              {:ok, rule()} | {:error, term()}
  @callback list_history(organization_id(), opts :: keyword()) :: [history_entry()]
  @callback test_channel(channel()) :: :ok | {:error, term()}

  @doc """
  Records a rule-less event in alert history (e.g. a bulk DLQ replay run).

  Unlike a fired rule, these events have no `alert_rule` association; the
  `event` map carries its own `trigger_type` plus `trigger_data`/`channels_sent`.
  Community is a no-op returning `:ok`, keeping callers total in builds without a
  Postgres-backed provider.
  """
  @callback record_event(organization_id(), event :: map()) :: :ok
end
