defmodule Flux.Sink.Adapter do
  @moduledoc """
  Contract for sink adapter modules.

  A sink adapter delivers pipeline data to an external destination — HTTP
  endpoint, database, object store, queue, etc. Adapters register themselves
  against a string type identifier at boot via `Flux.Sink.Registry.register/2`
  and are looked up at dispatch time by `Flux.Sink.deliver/3`.

  Adapters shipped with Community: `Flux.Sink.Adapters.HTTP`,
  `Flux.Sink.Adapters.Postgres`. Pro/EE adapters (e.g. S3, Snowflake,
  BigQuery, Kafka) ship in the commercial edition and register themselves at
  boot; in Community builds the type identifier is backed by
  `Flux.Sink.Adapters.Stub`, which returns `{:error, {:pro_required, _}}`.
  """

  @type data :: map()
  @type sink_config :: map()
  @type delivery_opts :: keyword()
  @type result :: :ok | {:ok, term()} | {:error, term()}
  @type validation_result :: :ok | {:error, [String.t()]}

  @callback deliver(data(), sink_config(), delivery_opts()) :: result()

  @callback validate_config(sink_config()) :: validation_result()

  @callback test_connection(sink_config()) :: :ok | {:error, term()}

  @optional_callbacks [test_connection: 1]
end
