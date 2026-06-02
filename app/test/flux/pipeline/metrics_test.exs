defmodule Flux.Pipeline.MetricsTest do
  use ExUnit.Case

  alias Flux.Pipeline.Metrics

  describe "snapshot/0" do
    test "returns metrics with expected keys" do
      snapshot = Metrics.snapshot()

      assert is_integer(snapshot.processed_total)
      assert is_integer(snapshot.failed_total)
      assert is_integer(snapshot.skipped_total)
      assert is_number(snapshot.events_per_sec)
      assert is_map(snapshot.per_pipeline)
    end
  end

  describe "telemetry event handling" do
    test "records processed events" do
      before = Metrics.snapshot().processed_total

      :telemetry.execute(
        [:flux, :pipeline, :message, :processed],
        %{duration: 1_000_000, count: 1},
        %{pipeline_id: "test-metrics-proc-#{System.unique_integer([:positive])}"}
      )

      Process.sleep(50)

      after_snapshot = Metrics.snapshot()
      assert after_snapshot.processed_total == before + 1
    end

    test "records failed events" do
      before = Metrics.snapshot().failed_total

      :telemetry.execute(
        [:flux, :pipeline, :message, :failed],
        %{count: 1},
        %{pipeline_id: "test-metrics-fail-#{System.unique_integer([:positive])}"}
      )

      Process.sleep(50)

      after_snapshot = Metrics.snapshot()
      assert after_snapshot.failed_total == before + 1
    end

    test "records skipped events" do
      before = Metrics.snapshot().skipped_total

      :telemetry.execute(
        [:flux, :pipeline, :message, :skipped],
        %{count: 1},
        %{pipeline_id: "test-metrics-skip-#{System.unique_integer([:positive])}"}
      )

      Process.sleep(50)

      after_snapshot = Metrics.snapshot()
      assert after_snapshot.skipped_total == before + 1
    end

    test "tracks per-pipeline metrics" do
      pipeline_id = "test-per-pipe-#{System.unique_integer([:positive])}"

      :telemetry.execute(
        [:flux, :pipeline, :message, :processed],
        %{duration: 500_000, count: 1},
        %{pipeline_id: pipeline_id}
      )

      Process.sleep(50)

      snapshot = Metrics.snapshot()
      assert Map.has_key?(snapshot.per_pipeline, pipeline_id)
      assert snapshot.per_pipeline[pipeline_id].processed == 1
    end
  end
end
