defmodule Flux.Load.Result do
  @moduledoc """
  The outcome of a single benchmark run.

  Durations are microseconds. `:throughput_per_sec` counts messages *handled*
  (processed + skipped + failed) over the wall-clock window. `:extra` carries
  benchmark-specific detail (e.g. sink delivered/received counts, full stats).
  """

  @enforce_keys [:name]
  defstruct name: nil,
            sent: 0,
            processed: 0,
            failed: 0,
            skipped: 0,
            elapsed_ms: 0,
            throughput_per_sec: 0.0,
            p50_us: 0,
            p95_us: 0,
            p99_us: 0,
            extra: %{}

  @type t :: %__MODULE__{}
end
