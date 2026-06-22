defmodule Flux.Load.Scenario do
  @moduledoc """
  Orchestrates one benchmark run end to end: build a pipeline from a step spec,
  start its Broadway runner, drive synthetic load, drain, and tear everything
  down — returning a `Flux.Load.Result`.

  Reuses the live engine (`Flux.Pipelines.create_pipeline/1`,
  `Flux.Pipeline.Manager.start_pipeline/1`) so the numbers reflect the real
  message path, not a mock.

  Callers that already have an organization (tests) pass `:organization_id`;
  the Mix task omits it and a dedicated benchmark org is created or reused.
  """

  alias Flux.Accounts
  alias Flux.Accounts.Scope
  alias Flux.Load.{Collector, Generator, Result, Stats}
  alias Flux.Pipeline.Manager
  alias Flux.Pipelines
  alias Flux.Repo
  alias Flux.Structure
  alias Flux.Structure.Organization

  @bench_slug "flux-benchmark"
  @warmup_ms 200
  @default_drain_ms 60_000

  @doc """
  Runs a single-pipeline benchmark.

  ## Options

    * `:name` (required) — label for the result.
    * `:steps` (required) — list of step-IR maps for the pipeline.
    * `:organization_id` — reuse an existing org (else a benchmark org is used).
    * `:concurrency` — Broadway processor concurrency (default 10).
    * `:sink_ids` — sink ids to deliver to (default `[]`).
    * `:gen_fun`, `:rate`, `:count`, `:duration_ms` — passed to the generator.
    * `:drain_timeout_ms` — max wait for in-flight messages to drain.
  """
  def run(opts) do
    name = Keyword.fetch!(opts, :name)
    org_id = resolve_org(opts)
    steps = Keyword.fetch!(opts, :steps)

    pipeline =
      create_bench_pipeline(
        name,
        org_id,
        steps,
        Keyword.get(opts, :concurrency, 10),
        Keyword.get(opts, :sink_ids, [])
      )

    {:ok, collector} = Collector.start_link(pipeline_ids: [pipeline.id])
    {:ok, _pid} = Manager.start_pipeline(pipeline.id)
    Process.sleep(@warmup_ms)

    try do
      t0 = now()

      {sent, _gen_ms} =
        Generator.run(
          queues: [pipeline.source_queue],
          gen_fun: Keyword.get(opts, :gen_fun, &default_payload/1),
          rate: Keyword.get(opts, :rate, 0),
          count: Keyword.get(opts, :count),
          duration_ms: Keyword.get(opts, :duration_ms)
        )

      drain(collector, sent, Keyword.get(opts, :drain_timeout_ms, @default_drain_ms))
      build_result(name, sent, Collector.flush(collector), now() - t0)
    after
      teardown([pipeline], collector)
    end
  end

  @doc """
  Runs a fan-out benchmark across `:pipelines` identical pipelines to measure the
  scaling factor / scheduler ceiling. Messages are spread round-robin across all
  source queues; the collector aggregates across them.
  """
  def run_fanout(opts) do
    name = Keyword.fetch!(opts, :name)
    org_id = resolve_org(opts)
    steps = Keyword.fetch!(opts, :steps)
    n = Keyword.fetch!(opts, :pipelines)
    concurrency = Keyword.get(opts, :concurrency, 10)

    pipelines =
      for i <- 1..n,
          do: create_bench_pipeline("#{name}-#{i}", org_id, steps, concurrency, [])

    ids = Enum.map(pipelines, & &1.id)
    queues = Enum.map(pipelines, & &1.source_queue)

    {:ok, collector} = Collector.start_link(pipeline_ids: ids)
    Enum.each(ids, &Manager.start_pipeline/1)
    Process.sleep(@warmup_ms)

    try do
      t0 = now()

      {sent, _gen_ms} =
        Generator.run(
          queues: queues,
          gen_fun: Keyword.get(opts, :gen_fun, &default_payload/1),
          rate: Keyword.get(opts, :rate, 0),
          count: Keyword.get(opts, :count),
          duration_ms: Keyword.get(opts, :duration_ms)
        )

      drain(collector, sent, Keyword.get(opts, :drain_timeout_ms, @default_drain_ms))

      result = build_result(name, sent, Collector.flush(collector), now() - t0)
      %{result | extra: Map.put(result.extra, :pipelines, n)}
    after
      teardown(pipelines, collector)
    end
  end

  @doc """
  Ensures a dedicated benchmark organization exists (idempotent across dev runs);
  returns its id. Creates a throwaway owner user the first time.
  """
  def ensure_org do
    case Repo.get_by(Organization, slug: @bench_slug) do
      %Organization{id: id} ->
        id

      nil ->
        email = "benchmark+#{System.unique_integer([:positive])}@flux.local"
        {:ok, user} = Accounts.register_user(%{email: email})

        {:ok, org} =
          Structure.create_organization(Scope.for_user(user), %{
            name: "Flux Benchmark",
            slug: @bench_slug
          })

        org.id
    end
  end

  # -- Private --

  defp resolve_org(opts), do: Keyword.get_lazy(opts, :organization_id, &ensure_org/0)

  defp create_bench_pipeline(name, org_id, steps, concurrency, sink_ids) do
    source_queue = "bench_#{System.unique_integer([:positive])}"

    {:ok, pipeline} =
      Pipelines.create_pipeline(%{
        name: "bench-#{name}",
        source_queue: source_queue,
        organization_id: org_id,
        status: "active",
        sink_ids: sink_ids,
        config: %{"processors" => %{"concurrency" => concurrency}},
        steps: %{"version" => "1", "steps" => steps}
      })

    pipeline
  end

  defp drain(collector, sent, timeout) do
    deadline = now() + timeout
    do_drain(collector, sent, deadline)
  end

  defp do_drain(collector, sent, deadline) do
    flushed = Collector.flush(collector)
    handled = flushed.processed + flushed.skipped + flushed.failed

    cond do
      handled >= sent -> :ok
      now() >= deadline -> :timeout
      true -> Process.sleep(50) && do_drain(collector, sent, deadline)
    end
  end

  defp build_result(name, sent, flushed, elapsed_ms) do
    stats = Stats.summary(flushed.durations)
    handled = flushed.processed + flushed.skipped + flushed.failed
    elapsed_ms = max(elapsed_ms, 1)

    %Result{
      name: name,
      sent: sent,
      processed: flushed.processed,
      failed: flushed.failed,
      skipped: flushed.skipped,
      elapsed_ms: elapsed_ms,
      throughput_per_sec: Float.round(handled * 1000 / elapsed_ms, 1),
      p50_us: stats.p50,
      p95_us: stats.p95,
      p99_us: stats.p99,
      extra: %{
        sink_delivered: flushed.sink_delivered,
        mean_us: Float.round(stats.mean, 1),
        min_us: stats.min,
        max_us: stats.max,
        sample_count: stats.count
      }
    }
  end

  defp teardown(pipelines, collector) do
    Enum.each(pipelines, fn pipeline ->
      safe(fn -> Manager.stop_pipeline(pipeline.id) end)
      safe(fn -> Pipelines.delete_pipeline(pipeline) end)
    end)

    safe(fn -> Collector.stop(collector) end)
  end

  defp default_payload(i) do
    %{"id" => i, "value" => :rand.uniform(1000)}
  end

  defp safe(fun) do
    fun.()
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp now, do: System.monotonic_time(:millisecond)
end
