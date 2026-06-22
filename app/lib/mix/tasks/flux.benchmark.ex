defmodule Mix.Tasks.Flux.Benchmark do
  @shortdoc "Runs the pipeline load/benchmark suite and reports latency & throughput"

  @moduledoc """
  Benchmarks the Flux pipeline engine and reports per-message latency percentiles
  and sustained throughput, then writes a Markdown report under `bench/results/`.

  ## Examples

      # Ad-hoc: 10 pipelines, 60s, filter+map steps
      mix flux.benchmark --pipelines 10 --duration 60 --steps filter,map

      # A named preset
      mix flux.benchmark --benchmark webhook_ingestion

      # The whole suite — count-based, bounded and reproducible (recommended)
      mix flux.benchmark --benchmark all

  ## Options

    * `--pipelines` / `-p` — number of concurrent pipelines (ad-hoc mode; default 1)
    * `--duration` / `-d`  — run window in seconds (default 30; ad-hoc & presets)
    * `--steps` / `-s`     — comma-separated step ops for ad-hoc mode (default `filter,map`);
                             one of `filter`, `map`, `rename`, `lua`
    * `--rate` / `-r`      — target messages/sec; `0` (default) means max throughput
    * `--concurrency` / `-c` — Broadway processor concurrency per pipeline (default 10)
    * `--benchmark` / `-b` — run a named preset (or `all`) instead of ad-hoc steps
    * `--report`           — output path for the Markdown report
    * `--log-level`        — log level during the run (default `warning`); one of
                             `debug`, `info`, `warning`, `error`, `none`. The run
                             is quiet by default so per-query/per-request debug
                             logs don't clutter output or skew the numbers; pass
                             `--log-level debug` to see them.

  ## A note on `--duration` with `--benchmark all`

  `--duration` is a **per-preset** window, not a total budget for the suite —
  `all` runs the presets sequentially, so a duration applies to each one in turn.
  It is also only honored by the engine presets (the latency and concurrency
  runs); the count-based presets (`webhook_ingestion`, `http_sink_delivery`,
  `postgres_sink_delivery`) use a fixed message count and ignore it.

  For the full suite, prefer the **count-based** form (`--benchmark all` with no
  `--duration`): it uses each preset's default message count, which is bounded
  and reproducible and finishes in ~1–2 minutes. Reserve `--duration` for a
  single ad-hoc or named-preset run when you want a timed window — note that a
  long duration at max rate (`--rate 0`) builds a large in-memory producer
  backlog that is then drained after the window closes.
  """

  use Mix.Task

  alias Flux.Load.{Benchmarks, Report, Scenario}

  @switches [
    pipelines: :integer,
    duration: :integer,
    steps: :string,
    rate: :integer,
    concurrency: :integer,
    benchmark: :string,
    report: :string,
    log_level: :string
  ]

  @aliases [p: :pipelines, d: :duration, s: :steps, r: :rate, c: :concurrency, b: :benchmark]

  # Whitelisted so user input never reaches String.to_atom/1. Quiet by default:
  # at :debug the per-query/per-request log lines both clutter output and skew the
  # numbers (formatting + stdout writes on the hot path).
  @log_levels %{
    "debug" => :debug,
    "info" => :info,
    "warning" => :warning,
    "warn" => :warning,
    "error" => :error,
    "none" => :none
  }

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(args, strict: @switches, aliases: @aliases)

    with_log_level(log_level(opts), fn ->
      results =
        case opts[:benchmark] do
          nil -> [ad_hoc(opts)]
          "all" -> Benchmarks.run_all(preset_opts(opts))
          name -> [run_named(name, opts)]
        end

      IO.puts("\n" <> Report.table(results))
      path = Report.write(results, report_opts(opts))
      IO.puts("Report written to #{path}")
    end)
  end

  # Raise the log level for the run (quieter, more accurate) and restore it after.
  defp with_log_level(level, fun) do
    previous = Logger.level()
    Logger.configure(level: level)

    try do
      fun.()
    after
      Logger.configure(level: previous)
    end
  end

  defp log_level(opts) do
    case opts[:log_level] do
      nil -> :warning
      value -> Map.get(@log_levels, String.downcase(value), :warning)
    end
  end

  defp run_named(name, opts) do
    if name in Benchmarks.presets() do
      Benchmarks.run_preset(name, preset_opts(opts))
    else
      Mix.raise(
        "Unknown benchmark #{inspect(name)}. Available: #{Enum.join(Benchmarks.presets(), ", ")}"
      )
    end
  end

  defp ad_hoc(opts) do
    steps =
      (opts[:steps] || "filter,map")
      |> String.split(",", trim: true)
      |> Enum.map(&Benchmarks.step_ir/1)

    base = [
      name: "adhoc",
      steps: steps,
      concurrency: Keyword.get(opts, :concurrency, 10),
      rate: Keyword.get(opts, :rate, 0),
      duration_ms: duration_ms(opts)
    ]

    case Keyword.get(opts, :pipelines, 1) do
      n when n > 1 -> Scenario.run_fanout([{:pipelines, n} | base])
      _ -> Scenario.run(base)
    end
  end

  # Presets accept a duration window override; everything else uses preset defaults.
  defp preset_opts(opts) do
    case opts[:duration] do
      nil -> []
      _ -> [duration_ms: duration_ms(opts)]
    end
  end

  defp report_opts(opts) do
    case opts[:report] do
      nil -> []
      path -> [dir: Path.dirname(path)]
    end
  end

  defp duration_ms(opts), do: Keyword.get(opts, :duration, 30) * 1000
end
