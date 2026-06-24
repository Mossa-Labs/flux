defmodule Flux.Source.Supervisor do
  @moduledoc """
  DynamicSupervisor for *active* source ingestion processes.

  Active sources (e.g. Kafka, in the commercial edition) run a long-lived
  consumer that publishes onto the internal queue. This supervisor owns those
  processes. Passive sources (webhook, poll) have no process, so starting them
  here is a no-op.

  In Community builds no registered source type returns an `ingestion_spec/2`
  (webhook/poll are passive; Kafka is the Pro stub), so this supervisor stays
  empty — it exists as the seam the EE Kafka adapter plugs into, mirroring how
  `Flux.Pipeline.DynamicSupervisor` hosts pipeline runners.
  """

  use DynamicSupervisor

  require Logger

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts the ingestion process for a source if it is active.

  Returns `{:ok, pid}` for an active source, `{:ok, :passive}` when the source
  type needs no process, or `{:error, reason}` if the process fails to start.
  """
  @spec start_source(String.t(), map(), keyword()) ::
          {:ok, pid()} | {:ok, :passive} | {:error, term()}
  def start_source(type, config, opts \\ []) do
    case Flux.Source.ingestion_spec(type, config, opts) do
      nil ->
        {:ok, :passive}

      spec ->
        case DynamicSupervisor.start_child(__MODULE__, spec) do
          {:ok, pid} ->
            {:ok, pid}

          {:error, {:already_started, pid}} ->
            {:ok, pid}

          {:error, reason} = error ->
            Logger.error(
              "[Flux.Source.Supervisor] failed to start #{type} source: #{inspect(reason)}"
            )

            error
        end
    end
  end

  @doc "Stops a running ingestion process started via `start_source/3`."
  @spec stop_source(pid()) :: :ok | {:error, :not_found}
  def stop_source(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
