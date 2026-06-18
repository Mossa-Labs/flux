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
  """

  alias Flux.Queue.Message

  @type queue_name :: String.t() | atom()
  @type publish_opts :: keyword()
  @type error :: {:error, term()}

  @typedoc """
  A failed message peeked from the dead-letter queue. `delivery_tag` is the
  broker-assigned handle used by `retry_message/1` and `discard_message/1`;
  it is only valid for the adapter session that produced it. `source` is the
  originating producer identifier (the published `Message.source`), surfaced so
  the DLQ UI and `replay_dlq/2` can filter by it.
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
  Filter for `replay_dlq/2`. All keys are optional and combined with AND. An
  empty map matches every dead-lettered message.

    * `:time_range` - `%{from: DateTime.t(), to: DateTime.t()}`, matched against
      the message's dead-letter `timestamp`.
    * `:queue` - exact match on `original_queue`.
    * `:source` - exact match on `source`.
  """
  @type replay_filters :: %{
          optional(:time_range) => %{from: DateTime.t(), to: DateTime.t()},
          optional(:queue) => String.t(),
          optional(:source) => String.t()
        }

  @typedoc """
  Result of one `replay_dlq/2` batch. `replayed` + `skipped` is the number of
  messages drained from the DLQ this call; `exhausted?` is `true` once fewer
  than `limit` messages remained, signalling the caller to stop looping.
  """
  @type replay_result :: %{
          replayed: non_neg_integer(),
          skipped: non_neg_integer(),
          exhausted?: boolean()
        }

  @callback publish(queue_name(), Message.t(), publish_opts()) :: :ok | error()

  @callback ack(Message.t()) :: :ok | error()

  @callback reject(Message.t(), requeue :: boolean()) :: :ok | error()

  @doc """
  Returns the Broadway producer child spec for this adapter, used by
  `Flux.Pipeline.Runner` to consume messages. Community's Memory adapter
  and EE's RabbitMQ/Kafka adapters each provide their own implementation.
  """
  @callback producer_spec(opts :: keyword()) :: {module(), keyword()} | nil

  @doc """
  Dead-letter queue management. These are Pro features: only the EE broker
  adapters implement them. Community's Memory adapter omits them (no DLQ),
  and the public `Stub` returns `{:error, {:pro_required, :dlq}}`. The
  `Flux.Queue` facade guards calls with `function_exported?/3` so an adapter
  that omits them never crashes the caller.
  """
  @callback list_dlq_messages(count :: non_neg_integer(), offset :: non_neg_integer()) ::
              {:ok, [dlq_message()]} | error()

  @callback get_dlq_depth() :: {:ok, non_neg_integer()} | error()

  @callback retry_message(delivery_tag :: term()) :: :ok | error()

  @callback discard_message(delivery_tag :: term()) :: :ok | error()

  @doc """
  Bulk-replays dead-lettered messages matching `filters` back to their original
  queues, in a single broker session, up to `limit` messages per call.

  Returns `{:ok, replay_result()}`; the caller (`Flux.Workers.ReplayWorker`)
  loops until `exhausted?` is `true`. Implementations must leave non-matching
  messages in the DLQ. This is a Pro feature; only EE broker adapters implement
  it.
  """
  @callback replay_dlq(filters :: replay_filters(), limit :: pos_integer()) ::
              {:ok, replay_result()} | error()

  @optional_callbacks [
    producer_spec: 1,
    list_dlq_messages: 2,
    get_dlq_depth: 0,
    retry_message: 1,
    discard_message: 1,
    replay_dlq: 2
  ]
end
