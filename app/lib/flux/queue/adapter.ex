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
  it is only valid for the adapter session that produced it.
  """
  @type dlq_message :: %{
          delivery_tag: term(),
          original_queue: String.t() | nil,
          reason: String.t() | nil,
          timestamp: DateTime.t() | nil,
          payload: map()
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

  @optional_callbacks [
    producer_spec: 1,
    list_dlq_messages: 2,
    get_dlq_depth: 0,
    retry_message: 1,
    discard_message: 1
  ]
end
