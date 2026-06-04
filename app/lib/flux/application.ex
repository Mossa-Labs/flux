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
      # Phoenix.PubSub's default PG2 adapter. Single-node in the Community build;
      # the Pro build forms a cluster (DNSCluster) so broadcasts fan out.
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
      # Pipeline process registry + supervisor for the single-node (Community)
      # backend (`Flux.Pipeline.Supervision.Local`). The `:unique` registry keeps
      # a pipeline running at most once on this node. The Pro build starts its own
      # Horde-backed registry/supervisor and routes through them instead.
      {Registry, keys: :unique, name: Flux.Pipeline.Registry},
      {DynamicSupervisor, name: Flux.Pipeline.DynamicSupervisor, strategy: :one_for_one},
      # Pipeline metrics aggregator (must start before Manager)
      Flux.Pipeline.Metrics,
      # Pipeline manager (auto-starts active pipelines)
      Flux.Pipeline.Manager,
      # Start to serve requests, typically the last entry
      FluxWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Flux.Supervisor]
    result = Supervisor.start_link(children, opts)
    warn_if_clustered()
    result
  end

  # The Community edition is single-node only: pipeline supervision is local
  # (`Flux.Pipeline.Supervision.Local`), so connected peers are ignored and a
  # pipeline can end up running on every node. Warn loudly if a cluster is
  # detected. Horizontal scaling / HA is a Pro feature (the Pro build supplies
  # the distributed, Horde-backed supervision backend).
  defp warn_if_clustered do
    if Node.list() != [] do
      require Logger

      Logger.warning(
        "[HA] Connected BEAM peers detected (#{inspect(Node.list())}), but the " <>
          "Community edition is single-node only. Peers are ignored and pipelines " <>
          "are NOT coordinated across nodes — upgrade to Flux Pro for horizontal " <>
          "scaling and high availability."
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
