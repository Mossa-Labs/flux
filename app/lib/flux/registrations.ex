defmodule Flux.Registrations do
  @moduledoc """
  Performs boot-time registration of Community adapters / strategies /
  providers into their respective registries. Runs as a one-shot
  supervision child that populates ETS tables and stays alive as a
  sentinel (so a crash-restart re-registers everything).

  The commercial edition boots a mirror module that registers its own Pro/EE
  modules on top of the Community base.
  """

  use GenServer

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    register_community()
    {:ok, :registered}
  end

  # Maps a queue type identifier to the license feature it requires. Types
  # absent from this map (e.g. "memory") are always available.
  @queue_features %{"rabbitmq" => :rabbit_mq_queue, "kafka" => :kafka_queue}

  defp register_community do
    :ok = register_sinks()
    :ok = register_queues()
    :ok = register_steps()
    :ok = register_auth_strategies()
    :ok = register_ai_provider()
    :ok = register_metering_provider()
    :ok = seed_active_queue()

    Logger.info("[Flux.Registrations] Community adapters registered")
    :ok
  end

  defp register_sinks do
    Flux.Sink.Registry.register("http", Flux.Sink.Adapters.HTTP)
    Flux.Sink.Registry.register("postgres", Flux.Sink.Adapters.Postgres)
    Flux.Sink.Registry.register("s3", Flux.Sink.Adapters.Stub)
    :ok
  end

  defp register_queues do
    Flux.Queue.Registry.register("memory", Flux.Queue.Adapters.Memory)
    Flux.Queue.Registry.register("rabbitmq", Flux.Queue.Adapters.Stub)
    :ok
  end

  defp register_steps do
    Flux.Pipeline.StepRegistry.register("map", Flux.Pipeline.Steps.Map)
    Flux.Pipeline.StepRegistry.register("filter", Flux.Pipeline.Steps.Filter)
    Flux.Pipeline.StepRegistry.register("rename", Flux.Pipeline.Steps.Rename)
    :ok
  end

  defp register_auth_strategies do
    Flux.Auth.Registry.register(:password, Flux.Auth.Strategies.Password)
    Flux.Auth.Registry.register(:magic_link, Flux.Auth.Strategies.MagicLink)
    :ok
  end

  defp register_ai_provider do
    provider = Application.get_env(:flux, Flux.AI)[:provider] || Flux.AI.Providers.Basic
    Flux.AI.Registry.set_active(provider)
    :ok
  end

  defp register_metering_provider do
    provider =
      Application.get_env(:flux, Flux.Metering)[:provider] || Flux.Metering.Providers.Community

    Flux.Metering.Registry.set_active(provider)
    :ok
  end

  @doc """
  Seeds the active queue adapter from `config :flux, Flux.Queue, type:`.

  Entitlement-aware and idempotent: if the configured type requires a license
  feature the current tier is not entitled to (e.g. `"rabbitmq"` on a
  Community build), it logs a warning and falls back to `"memory"` so the app
  still boots with a working queue. The commercial edition re-invokes this
  after registering its real Pro adapters, at which point the entitled type is
  honored.
  """
  @spec seed_active_queue() :: :ok | {:error, :unknown_type}
  def seed_active_queue do
    configured = Application.get_env(:flux, Flux.Queue)[:type] || "memory"
    set_active_queue(configured, Map.get(@queue_features, configured))
  end

  defp set_active_queue(type, nil), do: Flux.Queue.Registry.set_active(type)

  defp set_active_queue(type, feature) do
    if Flux.License.has_feature?(feature) do
      Flux.Queue.Registry.set_active(type)
    else
      Logger.warning(
        "[Flux.Registrations] Queue type #{inspect(type)} requires #{inspect(feature)} " <>
          "which the current license tier does not include. Falling back to \"memory\"."
      )

      Flux.Queue.Registry.set_active("memory")
    end
  end
end
