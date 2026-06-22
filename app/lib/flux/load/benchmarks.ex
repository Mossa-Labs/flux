defmodule Flux.Load.Benchmarks do
  @moduledoc """
  The named benchmark suite for performance validation.

  Each preset returns a `Flux.Load.Result`. The two headline claims are checked
  by these presets:

    * **message processing latency** — `passthrough_latency`,
      `native_steps_latency`, `script_lua_latency` report p50/p95/p99 of the
      per-message processing `duration`.
    * **sustained throughput** — `concurrency_50` (and friends) report
      messages/sec; multiply by 60 for messages/minute.

  Network-bound presets (`webhook_ingestion`, `http_sink_delivery`,
  `postgres_sink_delivery`) stand up their own targets and tear them down.

  `step_ir/1` is also used by the `mix flux.benchmark --steps` ad-hoc path.
  """

  alias Flux.Load.{Echo, Result, Scenario, Stats}

  @presets ~w(passthrough_latency native_steps_latency script_lua_latency
              concurrency_10 concurrency_50 webhook_ingestion
              http_sink_delivery postgres_sink_delivery)

  @lua_code """
  function transform(data)
    data.doubled = data.value * 2
    return data
  end
  """

  @doc "All available preset names."
  def presets, do: @presets

  @doc "Runs every preset and returns the list of results."
  def run_all(opts \\ []), do: Enum.map(@presets, &run_preset(&1, opts))

  @doc """
  Builds the step-IR map for a single operation token (used by `--steps`).
  """
  def step_ir("filter"),
    do: %{
      "type" => "native",
      "operation" => "filter",
      "config" => %{"field" => "value", "operator" => "gte", "value" => 0}
    }

  def step_ir("map"),
    do: %{
      "type" => "native",
      "operation" => "map",
      "config" => %{"field" => "value", "to" => "value_out"}
    }

  def step_ir("rename"),
    do: %{
      "type" => "native",
      "operation" => "rename",
      "config" => %{"from" => "value", "to" => "renamed"}
    }

  def step_ir(lua) when lua in ["script", "lua"],
    do: %{"type" => "script", "language" => "lua", "code" => @lua_code, "timeout_ms" => 5000}

  @doc "Runs one preset by name."
  def run_preset("passthrough_latency", opts),
    do: latency_run("passthrough_latency", [], 200_000, opts)

  def run_preset("native_steps_latency", opts),
    do:
      latency_run(
        "native_steps_latency",
        [step_ir("filter"), step_ir("map"), step_ir("rename")],
        200_000,
        opts
      )

  def run_preset("script_lua_latency", opts),
    do: latency_run("script_lua_latency", [step_ir("lua")], 100_000, opts)

  def run_preset("concurrency_10", opts), do: fanout_run("concurrency_10", 10, 500_000, opts)

  def run_preset("concurrency_50", opts), do: fanout_run("concurrency_50", 50, 1_000_000, opts)

  def run_preset("webhook_ingestion", opts), do: webhook_ingestion(opts)

  def run_preset("http_sink_delivery", opts), do: http_sink_delivery(opts)

  def run_preset("postgres_sink_delivery", opts), do: postgres_sink_delivery(opts)

  # -- Engine presets (max-rate; report both latency percentiles and throughput) --

  defp latency_run(name, steps, default_count, opts) do
    Scenario.run(
      [name: name, steps: steps, rate: 0, concurrency: 10] ++ bounds(opts, default_count)
    )
  end

  defp fanout_run(name, pipelines, default_count, opts) do
    Scenario.run_fanout(
      [name: name, pipelines: pipelines, steps: [step_ir("map")], rate: 0, concurrency: 10] ++
        bounds(opts, default_count)
    )
  end

  # Prefer a duration window when the caller gave one (`--duration`); otherwise
  # run a fixed message count for reproducibility. Always thread through any
  # explicit organization_id (tests supply one; the Mix task does not).
  defp bounds(opts, default_count) do
    org = Keyword.take(opts, [:organization_id])

    case Keyword.get(opts, :duration_ms) do
      nil -> [count: Keyword.get(opts, :count, default_count)] ++ org
      ms -> [duration_ms: ms] ++ org
    end
  end

  # -- Webhook ingestion (drives the API endpoint in-process) --

  @doc """
  Benchmarks the webhook ingestion endpoint (`POST /api/webhooks/:source`),
  exercising auth + quota + queue publish via `FluxWeb.Endpoint.call/2`. Raises
  the per-key burst limit for the run so the limiter is not the bottleneck.
  """
  def webhook_ingestion(opts) do
    org_id = Keyword.get_lazy(opts, :organization_id, &Scenario.ensure_org/0)
    count = Keyword.get(opts, :count, 50_000)
    concurrency = Keyword.get(opts, :concurrency, 50)

    {:ok, raw, _key} =
      Flux.Accounts.create_api_key(org_id, %{
        name: "bench-#{System.unique_integer([:positive])}",
        role: "admin"
      })

    with_raised_burst_limit(fn ->
      per_worker = max(1, div(count, concurrency))
      t0 = System.monotonic_time(:millisecond)

      results =
        1..concurrency
        |> Task.async_stream(fn _ -> issue_requests(raw, per_worker) end,
          max_concurrency: concurrency,
          timeout: :infinity,
          ordered: false
        )
        |> Enum.flat_map(fn {:ok, list} -> list end)

      elapsed = max(System.monotonic_time(:millisecond) - t0, 1)
      summarize_webhook(results, elapsed)
    end)
  end

  defp issue_requests(api_key, n) do
    for _ <- 1..n do
      body = Jason.encode!(%{"event" => "bench", "value" => :rand.uniform(1000)})

      t0 = System.monotonic_time(:microsecond)

      conn =
        Plug.Test.conn(:post, "/api/webhooks/bench", body)
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("x-api-key", api_key)
        |> FluxWeb.Endpoint.call([])

      {conn.status, System.monotonic_time(:microsecond) - t0}
    end
  end

  defp summarize_webhook(results, elapsed_ms) do
    accepted = Enum.count(results, fn {status, _} -> status == 202 end)
    total = length(results)
    latencies = for {202, us} <- results, do: us
    stats = Stats.summary(latencies)

    %Result{
      name: "webhook_ingestion",
      sent: total,
      processed: accepted,
      failed: total - accepted,
      elapsed_ms: elapsed_ms,
      throughput_per_sec: Float.round(accepted * 1000 / elapsed_ms, 1),
      p50_us: stats.p50,
      p95_us: stats.p95,
      p99_us: stats.p99,
      extra: %{
        accepted: accepted,
        non_2xx: total - accepted,
        mean_us: Float.round(stats.mean, 1),
        max_us: stats.max
      }
    }
  end

  defp with_raised_burst_limit(fun) do
    key = FluxWeb.Plugs.BurstLimiter
    prev = Application.get_env(:flux, key)
    Application.put_env(:flux, key, limit: 100_000_000, window_ms: 1_000)

    try do
      fun.()
    after
      if prev, do: Application.put_env(:flux, key, prev), else: Application.delete_env(:flux, key)
    end
  end

  # -- Sink presets --

  @doc "Benchmarks HTTP sink delivery against a local echo target."
  def http_sink_delivery(opts) do
    org_id = Keyword.get_lazy(opts, :organization_id, &Scenario.ensure_org/0)
    {:ok, echo} = Echo.start_link()

    {:ok, sink} =
      Flux.Sinks.create_sink(%{
        name: "bench-http-#{System.unique_integer([:positive])}",
        type: "http",
        organization_id: org_id,
        config: %{
          "url" => "http://127.0.0.1:#{echo.port}/",
          "method" => "POST",
          "retry" => %{"max_attempts" => 1}
        }
      })

    try do
      result =
        Scenario.run(
          [
            name: "http_sink_delivery",
            steps: [step_ir("map")],
            sink_ids: [sink.id],
            rate: 0,
            organization_id: org_id
          ] ++ [count: Keyword.get(opts, :count, 20_000)]
        )

      # Sink delivery is async (Task.start in the runner); give in-flight
      # deliveries a moment to land before reading the echo counter.
      Process.sleep(1_000)
      %{result | extra: Map.put(result.extra, :echo_received, Echo.count(echo))}
    after
      safe(fn -> Echo.stop(echo) end)
      safe(fn -> Flux.Sinks.delete_sink(sink) end)
    end
  end

  @doc """
  Benchmarks Postgres sink delivery into a throwaway table. Reports rows/sec and
  verifies the row count. NOTE: the adapter inserts one row per message (no
  batching) — this is the dominant cost and the report calls it out.
  """
  def postgres_sink_delivery(opts) do
    org_id = Keyword.get_lazy(opts, :organization_id, &Scenario.ensure_org/0)
    table = "bench_sink_#{System.unique_integer([:positive])}"

    Flux.Repo.query!(
      "CREATE TABLE #{table} (id bigint, value int, inserted_at timestamptz, updated_at timestamptz)"
    )

    {:ok, sink} =
      Flux.Sinks.create_sink(%{
        name: "bench-pg-#{System.unique_integer([:positive])}",
        type: "postgres",
        organization_id: org_id,
        config: %{
          "mode" => "internal",
          "table" => table,
          "columns" => %{"id" => "id", "value" => "value"},
          "on_conflict" => "nothing"
        }
      })

    try do
      result =
        Scenario.run(
          [
            name: "postgres_sink_delivery",
            steps: [step_ir("map")],
            sink_ids: [sink.id],
            rate: 0,
            organization_id: org_id
          ] ++ [count: Keyword.get(opts, :count, 20_000)]
        )

      Process.sleep(1_000)
      %{rows: [[inserted]]} = Flux.Repo.query!("SELECT count(*) FROM #{table}")
      %{result | extra: Map.put(result.extra, :rows_inserted, inserted)}
    after
      safe(fn -> Flux.Sinks.delete_sink(sink) end)
      safe(fn -> Flux.Repo.query!("DROP TABLE IF EXISTS #{table}") end)
    end
  end

  defp safe(fun) do
    fun.()
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end
end
