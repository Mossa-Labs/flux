defmodule Flux.License.Features do
  @moduledoc """
  Canonical source of truth for which features belong to which tier.

  The map is **cumulative**: `:enterprise ⊇ :pro ⊇ :community`. A license
  provider only reports a `tier/0`; `Flux.License.has_feature?/1` resolves
  entitlement against this map. Keeping the map here (in the public repo)
  lets the commercial edition's provider report a tier without re-declaring
  the feature catalog.

  ## Adding a new gated feature

    1. Add the feature atom to the appropriate tier below.
    2. Place the enforcement point here (interpreter, LiveView, context).
    3. Add the real implementation + registration in the commercial edition.

  Feature atoms gate the following:

    * `:s3_sink`, `:snowflake_sink`, `:bigquery_sink`, `:kafka_sink` - object/warehouse/stream sinks
    * `:redis_sink` - Redis sink connector (in-memory key-value / stream store)
    * `:mongodb_sink` - MongoDB sink connector (NoSQL document store)
    * `:slack_sink` - Slack sink connector (Incoming Webhook / bot-token messaging)
    * `:kafka_source` - Kafka topic source connector (see `Flux.Source`)
    * `:mqtt_source` - MQTT topic source connector for IoT/industrial ingestion
    * `:sqs_source` - Amazon SQS source connector (AWS managed queue)
    * `:kinesis_source` - Amazon Kinesis source connector (AWS streaming)
    * `:pubsub_source` - Google Pub/Sub source connector (GCP managed messaging)
    * `:rabbitmq_source` - external RabbitMQ broker source connector (distinct
      from the internal `:rabbit_mq_queue` backend)
    * `:sftp_source` - SFTP pull source connector (scheduled file ingestion)
    * `:rabbit_mq_queue`, `:dlq` - durable queue backend + dead-letter
    * `:advanced_ai` - anomaly detection step in the pipeline interpreter
    * `:live_signals` - the Live Signals monitoring page
    * `:cron_polling` - scheduled (cron) source polling
    * `:org_rbac` - organization-centric RBAC
    * `:api_key_scopes` - fine-grained (below-role) API key scopes
    * `:usage_metering` - per-org usage metering, usage card, and quota enforcement
    * `:alerting` - configurable alert rules + multi-channel notifications
    * `:observability` - freshness SLO, volume baseline & schema drift detectors
    * `:sso`, `:audit_log`, `:white_label` - enterprise auth/compliance
    * `:mfa_enforcement` - per-org "require MFA for all members" enforcement.
      Per-user TOTP MFA itself is Community; only org-wide enforcement is gated
      (MOS-591). The real enforcement ships in the commercial edition.
    * `:password_policy` - configurable per-org password policy (min length,
      character-class complexity, rotation). Ungated builds keep the min-12
      default; the real enforcement ships in the commercial edition.
    * `:pii_redaction` - in-flight PII redaction (`redact`) + sensitivity
      classification (`classify`) pipeline steps
  """

  @type tier :: :community | :pro | :enterprise
  @type feature :: atom()

  @tiers %{
    community: [],
    pro: [
      :s3_sink,
      :snowflake_sink,
      :bigquery_sink,
      :kafka_sink,
      # Redis sink connector — in-memory key-value/stream store (see `Flux.Sink`).
      :redis_sink,
      # MongoDB sink connector — NoSQL document store (see `Flux.Sink`).
      :mongodb_sink,
      # Slack sink connector — Incoming Webhook / bot-token messaging (see `Flux.Sink`).
      :slack_sink,
      # Kafka topic source connector (consume → transform/detect → produce).
      :kafka_source,
      # MQTT topic source connector — IoT/industrial ingestion (see `Flux.Source`).
      :mqtt_source,
      # Amazon SQS source connector — AWS managed queue (see `Flux.Source`).
      :sqs_source,
      # Amazon Kinesis source connector — AWS streaming (see `Flux.Source`).
      :kinesis_source,
      # Google Pub/Sub source connector — GCP managed messaging (see `Flux.Source`).
      :pubsub_source,
      # External RabbitMQ broker source connector — consumes a customer's own
      # broker (see `Flux.Source`). Distinct from `:rabbit_mq_queue`, the
      # internal durable-queue backend.
      :rabbitmq_source,
      # SFTP pull source connector — scheduled file ingestion from a remote
      # SFTP server, one message per parsed record (see `Flux.Source`).
      :sftp_source,
      :rabbit_mq_queue,
      :dlq,
      :advanced_ai,
      :live_signals,
      :cron_polling,
      # Org-centric RBAC is "Pro+" per MOS-458 — entitled from the Pro tier up.
      :org_rbac,
      # Restricting an API key's scopes below its role (least-privilege keys).
      :api_key_scopes,
      # Per-organization usage metering, the usage card, and quota enforcement.
      :usage_metering,
      # Configurable alert rules + email/webhook/Slack notifications (MOS-452).
      :alerting,
      # Freshness SLO, volume baseline & schema drift detection (MOS-472).
      :observability
    ],
    enterprise: [
      :sso,
      :audit_log,
      :white_label,
      # Per-org "require MFA for all members" enforcement. Per-user TOTP MFA is
      # Community (MOS-591); only org-wide enforcement is Enterprise-gated. The
      # Community build ships a no-op enforcement stub.
      :mfa_enforcement,
      # Configurable per-org password policy — min length, character-class
      # complexity, and rotation. The Community build keeps the min-12 default;
      # the real enforcement ships in the commercial edition (MOS-590).
      :password_policy,
      # In-flight PII redaction + sensitivity classification steps (MOS-480).
      # The real detectors ship in the Enterprise edition; the Community build
      # registers a pass-through stub for the `redact`/`classify` operations.
      :pii_redaction
    ]
  }

  @doc """
  Returns the cumulative feature set entitled to `tier`.

  `:enterprise` includes every `:pro` feature; `:pro` includes every
  `:community` feature.
  """
  @spec for_tier(tier()) :: [feature()]
  def for_tier(:community), do: @tiers.community
  def for_tier(:pro), do: @tiers.community ++ @tiers.pro
  def for_tier(:enterprise), do: @tiers.community ++ @tiers.pro ++ @tiers.enterprise

  @doc "All known feature atoms across every tier."
  @spec all() :: [feature()]
  def all, do: for_tier(:enterprise)

  @doc "The lowest tier that entitles `feature`, or `nil` if unknown."
  @spec tier_for_feature(feature()) :: tier() | nil
  def tier_for_feature(feature) when is_atom(feature) do
    cond do
      feature in @tiers.community -> :community
      feature in @tiers.pro -> :pro
      feature in @tiers.enterprise -> :enterprise
      true -> nil
    end
  end
end
