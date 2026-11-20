defmodule Flux.Source.Adapter do
  @moduledoc """
  Contract for source adapter modules.

  A *source* brings events from an external system into Flux. Unlike a sink
  (which is called per-message during processing), a source's job is to land
  events onto the internal queue — the same durable queue a pipeline's Broadway
  runner already consumes from. The internal/core queue backend is unchanged
  (Memory in dev, RabbitMQ in production); sources publish **into** it via
  `Flux.Queue.publish/4`, they are never a queue backend themselves.

  Every source belongs to one organization, and publishes into that
  organization's queues only: `Flux.Queue.publish(organization_id, queue_name,
  message, opts)`, with the organization taken from the `:organization_id`
  ingestion option, never from the source's config.

  Sources fall into two shapes:

    * **Passive** (push or scheduler driven) — e.g. `Webhook` (an HTTP request
      publishes) or `Poll` (an Oban job publishes). These need no long-lived
      process, so `ingestion_spec/2` returns `nil`.

    * **Active** (long-lived consumer) — e.g. Kafka, where a process continuously
      consumes a topic and publishes onto the internal queue. `ingestion_spec/2`
      returns a child spec started under `Flux.Source.Supervisor`.

  A pipeline links to a source by consuming the queue the source publishes to —
  `queue_name/1` is the single source of truth for that convention (e.g.
  `"webhooks.github"`, `"polling.orders"`, `"kafka.events"`), so every source
  type wires to pipelines the same way. These are *logical* names (see
  `Flux.Queue.Naming`): `Flux.Queue` places them inside the source's
  organization, so the same name in two organizations is two separate queues.

  Adapters shipped with Community: `Flux.Source.Adapters.Webhook`,
  `Flux.Source.Adapters.Poll`. Pro/EE adapters (e.g. Kafka) ship in the
  commercial edition and register themselves at boot; in Community builds the
  type identifier is backed by `Flux.Source.Adapters.Stub`, which returns
  `{:error, {:pro_required, _}}`.
  """

  @type source_config :: map()
  @type validation_result :: :ok | {:error, [String.t()]}

  @doc """
  The logical internal queue name a pipeline should consume from for this source.

  This is the convention that links a source to the pipelines fed by it. The
  config carries whatever identifier the type keys on (e.g. `"name"` /
  `"source"` for webhook, `"source_id"` for poll, topic/group for Kafka). The
  result must be a valid logical name (`Flux.Queue.Naming.validate_logical/1`);
  wrap parts that come from an external system in
  `Flux.Queue.Naming.sanitize_segment/1`.
  """
  @callback queue_name(source_config()) :: String.t()

  @doc """
  A long-lived ingestion process spec, or `nil` for passive sources.

  Active sources (e.g. Kafka) return a `Supervisor.child_spec()` for a process
  that consumes the external system and publishes onto `queue_name/1` via
  `Flux.Queue.publish/4`. Passive sources (webhook, poll) return `nil`.

  `opts` carries runtime context: `:source_id` and `:organization_id`. The
  process must publish into `:organization_id`'s queues, and refuse to start
  without one.
  """
  @callback ingestion_spec(source_config(), keyword()) :: Supervisor.child_spec() | nil

  @callback validate_config(source_config()) :: validation_result()

  @callback test_connection(source_config()) :: :ok | {:error, term()}

  @optional_callbacks [test_connection: 1, ingestion_spec: 2]
end
