defmodule Flux.Load.Report do
  @moduledoc """
  Renders benchmark results as a console table and a Markdown report artifact,
  including an explicit PASS/FAIL verdict on the two headline claims:

    * message processing p99 < 5ms
    * sustained throughput >= 1,000,000 messages/minute (>= 16,667 msg/sec)
  """

  alias Flux.Load.Result

  # 5ms in microseconds.
  @p99_target_us 5_000
  # 1,000,000 / minute.
  @throughput_target_per_sec 16_667

  @doc "Returns a fixed-width console table for a list of results."
  def table(results) when is_list(results) do
    header =
      row(["benchmark", "sent", "proc", "fail", "skip", "thr/s", "p50", "p95", "p99"])

    rule = String.duplicate("─", String.length(header))

    body = Enum.map_join(results, "\n", &result_row/1)

    """
    #{rule}
    #{header}
    #{rule}
    #{body}
    #{rule}
    #{verdict_line(results)}
    """
  end

  @doc """
  Writes a Markdown report. Returns the path. Defaults to
  `bench/results/benchmark-<timestamp>.md` (and refreshes `latest.md`).
  `timestamp` must be supplied by the caller (scripts can't read the clock).
  """
  def write(results, opts \\ []) do
    timestamp =
      Keyword.get_lazy(opts, :timestamp, fn -> DateTime.utc_now() |> DateTime.to_iso8601() end)

    dir = Keyword.get(opts, :dir, Path.join(File.cwd!(), "bench/results"))
    File.mkdir_p!(dir)

    content = markdown(results, timestamp, opts)
    safe_ts = String.replace(timestamp, ~r/[:.]/, "-")
    path = Path.join(dir, "benchmark-#{safe_ts}.md")

    File.write!(path, content)
    File.write!(Path.join(dir, "latest.md"), content)
    path
  end

  # -- Console rendering --

  defp result_row(%Result{} = r) do
    row([
      r.name,
      to_string(r.sent),
      to_string(r.processed),
      to_string(r.failed),
      to_string(r.skipped),
      format_float(r.throughput_per_sec),
      ms(r.p50_us),
      ms(r.p95_us),
      ms(r.p99_us)
    ])
  end

  defp row(cells) do
    [name | rest] = cells

    [String.pad_trailing(name, 24) | Enum.map(rest, &String.pad_leading(&1, 10))]
    |> Enum.join("")
  end

  defp verdict_line(results) do
    {p99_pass, p99_val} = p99_verdict(results)
    {thr_pass, thr_val} = throughput_verdict(results)

    "Claims:  p99 < 5ms -> #{pass(p99_pass)} (#{ms(p99_val)})    " <>
      "1M msgs/min -> #{pass(thr_pass)} (#{format_float(thr_val * 60)}/min)"
  end

  defp pass(true), do: "PASS"
  defp pass(false), do: "FAIL"

  # -- Verdict computation --

  # Worst p99 across the latency presets (those that actually collected samples).
  defp p99_verdict(results) do
    latency = Enum.filter(results, &(&1.p99_us > 0))

    case latency do
      [] ->
        {false, 0}

      _ ->
        worst = Enum.max_by(latency, & &1.p99_us).p99_us
        {worst < @p99_target_us, worst}
    end
  end

  # Best sustained throughput across all results.
  defp throughput_verdict(results) do
    best = results |> Enum.map(& &1.throughput_per_sec) |> Enum.max(fn -> 0.0 end)
    {best >= @throughput_target_per_sec, best}
  end

  # -- Markdown rendering --

  defp markdown(results, timestamp, opts) do
    {otp, ex} = versions()

    """
    # Flux Benchmark Results

    - **Timestamp:** #{timestamp}
    - **Git SHA:** #{Keyword.get(opts, :git_sha, git_sha())}
    - **Elixir:** #{ex} / **OTP:** #{otp}
    - **Schedulers online:** #{System.schedulers_online()}

    ## Summary

    ```
    #{String.trim_trailing(table(results))}
    ```

    ## Per-benchmark detail

    #{Enum.map_join(results, "\n", &detail/1)}

    ## Caveats

    - Single node; in-memory queue adapter (not the production durable broker).
    - Postgres sink inserts one row per message (no batching) — the dominant cost.
    - The webhook ingestion run raises the per-key burst limit so the limiter is not measured.
    - Latency is the per-message processing `duration` (step execution); it excludes time spent waiting in the producer queue.
    """
  end

  defp detail(%Result{} = r) do
    extra =
      r.extra
      |> Enum.map(fn {k, v} -> "  - #{k}: #{inspect(v)}" end)
      |> Enum.join("\n")

    """
    ### #{r.name}

    - sent: #{r.sent}, processed: #{r.processed}, failed: #{r.failed}, skipped: #{r.skipped}
    - throughput: #{format_float(r.throughput_per_sec)} msg/sec (#{format_float(r.throughput_per_sec * 60)} / min)
    - latency p50/p95/p99: #{ms(r.p50_us)} / #{ms(r.p95_us)} / #{ms(r.p99_us)}
    - extra:
    #{extra}
    """
  end

  # -- Formatting helpers --

  defp ms(us), do: "#{Float.round(us / 1000, 2)}ms"

  defp format_float(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp format_float(n), do: to_string(n)

  defp versions do
    {:erlang.system_info(:otp_release) |> to_string(), System.version()}
  end

  defp git_sha do
    case System.cmd("git", ["rev-parse", "--short", "HEAD"], stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _ -> "unknown"
    end
  rescue
    _ -> "unknown"
  end
end
