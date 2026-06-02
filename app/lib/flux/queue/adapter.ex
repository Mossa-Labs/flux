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

  @callback publish(queue_name(), Message.t(), publish_opts()) :: :ok | error()

  @callback ack(Message.t()) :: :ok | error()

  @callback reject(Message.t(), requeue :: boolean()) :: :ok | error()

  @doc """
  Returns the Broadway producer child spec for this adapter, used by
  `Flux.Pipeline.Runner` to consume messages. Community's Memory adapter
  and EE's RabbitMQ/Kafka adapters each provide their own implementation.
  """
  @callback producer_spec(opts :: keyword()) :: {module(), keyword()} | nil

  @optional_callbacks [producer_spec: 1]
end
