defmodule Flux.Source.Manager do
  @moduledoc """
  Auto-starts active source ingestion processes at boot.

  Mirrors `Flux.Pipeline.Manager`: on start it asynchronously walks every
  enabled source and asks `Flux.Source.Supervisor` to start its ingestion
  process. Passive sources (webhook, poll) are no-ops, so in Community builds
  this starts nothing — it is the boot hook the EE Kafka adapter relies on to
  bring its consumers up.
  """

  use GenServer

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Defer until the supervision tree (Repo, registries, Source.Supervisor) is up.
    send(self(), :auto_start)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:auto_start, state) do
    run_auto_start()
    {:noreply, state}
  end

  defp run_auto_start do
    sources = Flux.Sources.list_all_enabled_sources()
    active = Enum.reject(sources, &passive?/1)

    for source <- active do
      case Flux.Sources.start_ingestion(source) do
        {:ok, :passive} ->
          :ok

        {:ok, _pid} ->
          Logger.info(
            "[Flux.Source.Manager] started #{source.type} source #{source.id} (#{source.name})"
          )

        {:error, reason} ->
          Logger.error(
            "[Flux.Source.Manager] failed to start #{source.type} source #{source.id}: #{inspect(reason)}"
          )
      end
    end

    :ok
  rescue
    # Never let a source bring down the supervision tree at boot.
    error ->
      Logger.error("[Flux.Source.Manager] auto-start error: #{inspect(error)}")
      :ok
  end

  # A source is passive if its adapter advertises no ingestion process. We probe
  # via the facade so the check stays correct as EE swaps the Kafka stub for the
  # real adapter.
  defp passive?(source) do
    config = Map.put(source.config, "type", source.type)
    Flux.Source.ingestion_spec(source.type, config, source_id: source.id) == nil
  end
end
