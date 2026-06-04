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
      {DNSCluster, query: Application.get_env(:flux, :dns_cluster_query) || :ignore},
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
      # Pipeline process registry
      {Registry, keys: :unique, name: Flux.Pipeline.Registry},
      # Dynamic supervisor for pipeline runners
      {DynamicSupervisor, name: Flux.Pipeline.DynamicSupervisor, strategy: :one_for_one},
      # Pipeline metrics aggregator (must start before Manager)
      Flux.Pipeline.Metrics,
      # Pipeline manager (auto-starts active pipelines)
      Flux.Pipeline.Manager,
      # Start to serve requests, typically the last entry
      FluxWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Flux.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FluxWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
