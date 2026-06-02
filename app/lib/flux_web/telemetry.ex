defmodule FluxWeb.Telemetry do
  @moduledoc "Telemetry supervisor for collecting and reporting application metrics."
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("flux.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("flux.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("flux.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("flux.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("flux.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # Pipeline Metrics
      counter("flux.pipeline.message.processed.count",
        tags: [:pipeline_id],
        description: "Total messages successfully processed"
      ),
      summary("flux.pipeline.message.processed.duration",
        tags: [:pipeline_id],
        unit: {:native, :millisecond},
        description: "Processing duration per message"
      ),
      counter("flux.pipeline.message.failed.count",
        tags: [:pipeline_id],
        description: "Total messages that failed processing"
      ),
      counter("flux.pipeline.message.skipped.count",
        tags: [:pipeline_id],
        description: "Total messages skipped"
      ),
      counter("flux.pipeline.batch.failed.count",
        tags: [:pipeline_id],
        description: "Total batch failures"
      ),
      last_value("flux.pipeline.running.count",
        description: "Number of currently running pipelines"
      ),
      last_value("flux.pipeline.active.count",
        description: "Number of active pipelines in database"
      )
    ]
  end

  defp periodic_measurements do
    [
      {__MODULE__, :measure_pipeline_stats, []}
    ]
  end

  @doc false
  def measure_pipeline_stats do
    running_count =
      try do
        length(Flux.Pipeline.Manager.list_running())
      rescue
        _ -> 0
      end

    active_count =
      try do
        length(Flux.Pipelines.list_active_pipelines())
      rescue
        _ -> 0
      end

    :telemetry.execute(
      [:flux, :pipeline, :running],
      %{count: running_count},
      %{}
    )

    :telemetry.execute(
      [:flux, :pipeline, :active],
      %{count: active_count},
      %{}
    )
  end
end
