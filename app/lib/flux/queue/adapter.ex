defmodule Flux.Queue.Adapter do
  @moduledoc """
  Contract for queue adapter modules.

  A queue adapter publishes messages to and acknowledges messages from a
  message broker (in-memory, RabbitMQ, Kafka, etc.). Adapters register
  themselves against a string type identifier at boot via
  `Flux.Queue.Registry.register/2` and are looked up at dispatch time
  by the `Flux.Queue` facade.

  Adapters shipped with Community: `Flux.Queue.Adapters.Memory`.
  Pro/EE adapters (RabbitMQ, Kafka) ship in the commercial edition and register
  at boot; in Community builds a Pro type identifier is backed by
  `Flux.Queue.Adapters.Stub`, which returns `{:error, {:pro_required, _}}`.

  ## Organizations

  Every queue belongs to one organization. Callers name queues with logical
  names; the `Flux.Queue` facade turns them into *physical* names inside the
  organization's namespace (see `Flux.Queue.Naming`) before calling an adapter,
  so adapters only ever see physical names such as `"org.42.webhooks.stripe"`.

  An adapter must also carry each message's `organization_id` across the
  broker, so that a consuming pipeline can check it (see
  `c:message_organization_id/1`), and it must keep each organization's
  dead letters apart from every other organization's.
  """

  alias Flux.Queue.Message

  @type queue_name :: String.t() | atom()
  @type publish_opts :: keyword()
  @type error :: {:error, term()}

  @typedoc """
  A failed message peeked from an organization's dead-letter queue.
  `delivery_tag` is the broker-assigned handle used by `retry_message/2` and
  `discard_message/2`; it is only valid for the adapter session that produced
  it. `original_queue` is the *physical* queue the message was dead-lettered
  from. `source` is the originating producer identifier (the published
  `Message.source`), surfaced so the DLQ UI and `replay_dlq/3` can filter by it.
  """
  @type dlq_message :: %{
          delivery_tag: term(),
          original_queue: String.t() | nil,
          source: String.t() | nil,
          reason: String.t() | nil,
          timestamp: DateTime.t() | nil,
          payload: map()
        }

  @typedoc """
  Filter for `replay_dlq/3`. All keys are optional and combined with AND. An
  empty map matches every message in the organization's dead-letter queue.

    * `:time_range` - `%{from: DateTime.t(), to: DateTime.t()}`, matched against
      the message's dead-letter `timestamp`.
    * `:queue` - exact match on the *physical* `original_queue`.
    * `:source` - exact match on `source`.
  """
  @type replay_filters :: %{
          optional(:time_range) => %{from: DateTime.t(), to: DateTime.t()},
          optional(:queue) => String.t(),
          optional(:source) => String.t()
        }

  @typedoc """
  Result of one `replay_dlq/3` batch. `replayed` + `skipped` is the number of
  messages drained from the DLQ this call; `exhausted?` is `true` once fewer
  than `limit` messages remained, signalling the caller to stop looping.
  """
  @type replay_result :: %{
          replayed: non_neg_integer(),
          skipped: non_neg_integer(),
          exhausted?: boolean()
        }

  @type organization_id :: pos_integer()

  @doc """
  Publishes `message` to the physical queue `queue`.

  `Flux.Queue.publish/4` is the only caller: `queue` is already inside the
  organization's namespace and `message.organization_id` is set. The adapter
  must carry `organization_id` across the broker so `c:message_organization_id/1`
  can read it back, and should refuse a queue outside that organization's
  namespace (`Flux.Queue.Naming.check_owner/2`).
  """
  @callback publish(queue_name(), Message.t(), publish_opts()) :: :ok | error()

  @callback ack(Message.t()) :: :ok | error()

  @callback reject(Message.t(), requeue :: boolean()) :: :ok | error()

  @doc """
  Returns the Broadway producer child spec for this adapter, used by
  `Flux.Pipeline.Runner` to consume messages. Community's Memory adapter
  and EE's RabbitMQ/Kafka adapters each provide their own implementation.

  `opts` carries `:queue` (the physical queue to consume), `:organization_id`
  (its organization), `:pipeline_id` and `:prefetch_count`. An adapter that
  implements this callback must also implement `c:message_organization_id/1`.
  """
  @callback producer_spec(opts :: keyword()) :: {module(), keyword()} | nil

  @doc """
  Reads the organization a consumed message was published for.

  Called by `Flux.Pipeline.Runner` on every message its producer emits, before
  the message is processed; the runner refuses any message that doesn't carry
  the pipeline's own organization. Returns `:error` when the message carries no
  readable organization. Must not raise.
  """
  @callback message_organization_id(Broadway.Message.t()) :: {:ok, organization_id()} | :error

  @doc """
  Dead-letter queue management. These are Pro features: only the EE broker
  adapters implement them. Community's Memory adapter omits them (no DLQ),
  and the public `Stub` returns `{:error, {:pro_required, :dlq}}`. The
  `Flux.Queue` facade guards calls with `function_exported?/3` so an adapter
  that omits them never crashes the caller.

  Every DLQ callback acts on one organization's dead letters only. An
  organization must never see, count, retry, discard or replay another
  organization's dead letters, including by guessing a delivery tag.
  """
  @callback list_dlq_messages(
              organization_id(),
              count :: non_neg_integer(),
              offset :: non_neg_integer()
            ) :: {:ok, [dlq_message()]} | error()

  @callback get_dlq_depth(organization_id()) :: {:ok, non_neg_integer()} | error()

  @callback retry_message(organization_id(), delivery_tag :: term()) :: :ok | error()

  @callback discard_message(organization_id(), delivery_tag :: term()) :: :ok | error()

  @doc """
  Bulk-replays an organization's dead-lettered messages matching `filters` back
  to their original queues, in a single broker session, up to `limit` messages
  per call.

  Returns `{:ok, replay_result()}`; the caller (`Flux.Workers.ReplayWorker`)
  loops until `exhausted?` is `true`. Implementations must leave non-matching
  messages in the DLQ. This is a Pro feature; only EE broker adapters implement
  it.
  """
  @callback replay_dlq(organization_id(), filters :: replay_filters(), limit :: pos_integer()) ::
              {:ok, replay_result()} | error()

  @optional_callbacks [
    producer_spec: 1,
    message_organization_id: 1,
    list_dlq_messages: 3,
    get_dlq_depth: 1,
    retry_message: 2,
    discard_message: 2,
    replay_dlq: 3
  ]
end
