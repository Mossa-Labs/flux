defmodule Flux.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FluxWeb.Telemetry,
      Flux.Repo,
      # HA clustering: DNSCluster forms the BEAM cluster by resolving
      # DNS_CLUSTER_QUERY (see rel/env.sh.eex for node distribution). Disabled
      # (:ignore) when the query is unset — i.e. single-node / dev.
      {DNSCluster, query: Application.get_env(:flux, :dns_cluster_query) || :ignore},
      # Phoenix.PubSub's default PG2 adapter is cluster-aware: once nodes are
      # connected, broadcasts (metrics, pipeline producers) fan out cluster-wide.
      {Phoenix.PubSub, name: Flux.PubSub},
      # Registries for adapters / strategies / providers — must start before
      # Flux.Registrations so boot-time registrations have somewhere to land.
      Flux.Sink.Registry,
      Flux.Queue.Registry,
      Flux.Pipeline.StepRegistry,
      Flux.Auth.Registry,
      Flux.AI.Registry,
      # Community self-registration (EE adds its own registrations on top).
      Flux.Registrations,
      # Records API-key last_used_at off the request path.
      Flux.Accounts.ApiKeyUsage,
      # Active queue adapter — resolved from the registry at its own init time.
      Flux.Queue.Supervisor,
      # Active AI provider — starts a process only if the provider needs one.
      Flux.AI.Supervisor,
      # Oban for background jobs
      {Oban, Application.fetch_env!(:flux, Oban)},
      # Pipeline process registry — Horde.Registry so runner names are unique
      # cluster-wide (a pipeline runs on exactly one node). `members: :auto`
      # discovers peer registries over the connected cluster.
      {Horde.Registry, name: Flux.Pipeline.Registry, keys: :unique, members: :auto},
      # Distributed supervisor for pipeline runners — Horde relocates a dead
      # node's runners onto a surviving node (failover) and, with the unique
      # registry above, prevents the same pipeline running twice.
      {Horde.DynamicSupervisor,
       name: Flux.Pipeline.DynamicSupervisor, strategy: :one_for_one, members: :auto},
      # Pipeline metrics aggregator (must start before Manager)
      Flux.Pipeline.Metrics,
      # Pipeline manager (auto-starts active pipelines)
      Flux.Pipeline.Manager,
      # Start to serve requests, typically the last entry
      FluxWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Flux.Supervisor]
    result = Supervisor.start_link(children, opts)
    warn_if_ha_misconfigured()
    result
  end

  # HA safety: warn loudly if clustering is intended (DNS_CLUSTER_QUERY set) but
  # the in-memory queue is active. Memory loses data on failover, so HA
  # deployments must use a durable queue (RabbitMQ / Pro).
  defp warn_if_ha_misconfigured do
    clustering? = Application.get_env(:flux, :dns_cluster_query) not in [nil, :ignore, ""]

    memory_queue? =
      match?({:ok, Flux.Queue.Adapters.Memory}, Flux.Queue.Registry.active())

    if clustering? and memory_queue? do
      require Logger

      Logger.warning(
        "[HA] Clustering is enabled but the in-memory queue is active. The memory " <>
          "queue loses data on node failover — HA deployments must use a durable " <>
          "queue. Set FLUX_QUEUE_TYPE=rabbitmq (Pro)."
      )
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FluxWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
