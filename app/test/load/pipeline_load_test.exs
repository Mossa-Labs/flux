defmodule Flux.Pipeline.LoadTest do
  @moduledoc """
  Load test for pipeline processing back-pressure.

  Run with:
    mix test test/load/pipeline_load_test.exs --include load

  This test:
  1. Creates a pipeline with transformation steps
  2. Pushes messages at high volume through the Memory producer
  3. Measures throughput and verifies back-pressure behavior
  4. Checks that all messages are eventually processed
  """

  use Flux.DataCase, async: false

  alias Flux.Pipeline.Manager
  alias Flux.Pipeline.Metrics
  alias Flux.Pipeline.Producers.Memory, as: MemoryProducer
  alias Flux.Pipelines

  import Flux.AccountsFixtures
  import Flux.StructureFixtures

  @moduletag :load

  @message_count 10_000
  @batch_size 100

  setup do
    scope = user_scope_fixture()
    org = organization_fixture(scope)

    source_queue = "load_test_#{System.unique_integer([:positive])}"

    {:ok, pipeline} =
      Pipelines.create_pipeline(%{
        name: "Load Test Pipeline",
        source_queue: source_queue,
        organization_id: org.id,
        status: "active",
        config: %{"processors" => %{"concurrency" => 10}},
        steps: %{
          "version" => "1",
          "steps" => [
            %{
              "type" => "native",
              "operation" => "map",
              "config" => %{"fields" => ["id", "value"]}
            }
          ]
        }
      })

    # Record the baseline processed count before this test
    baseline = Metrics.snapshot().processed_total

    {:ok, _pid} = Manager.start_pipeline(pipeline.id)

    # Give Broadway time to start
    Process.sleep(200)

    on_exit(fn ->
      Manager.stop_pipeline(pipeline.id)
    end)

    %{pipeline: pipeline, source_queue: source_queue, baseline: baseline}
  end

  @tag :load
  test "processes high volume of messages with back-pressure", %{
    source_queue: source_queue,
    baseline: baseline
  } do
    start_time = System.monotonic_time(:millisecond)

    # Push messages in batches
    for batch <- 1..div(@message_count, @batch_size) do
      for i <- 1..@batch_size do
        msg_num = (batch - 1) * @batch_size + i

        MemoryProducer.push_message(source_queue, %{
          "id" => msg_num,
          "value" => :rand.uniform(1000),
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        })
      end

      # Small delay between batches to simulate realistic load
      Process.sleep(10)
    end

    # Wait for processing to complete
    wait_for_processing(@message_count, baseline, 30_000)

    elapsed = System.monotonic_time(:millisecond) - start_time
    throughput = @message_count / (elapsed / 1_000)

    IO.puts("\n=== Load Test Results ===")
    IO.puts("Messages sent: #{@message_count}")
    IO.puts("Total time: #{elapsed}ms")
    IO.puts("Throughput: #{Float.round(throughput, 1)} msg/sec")
    IO.puts("=========================\n")

    assert throughput > 100,
           "Expected throughput > 100 msg/sec, got #{Float.round(throughput, 1)}"
  end

  @tag :load
  test "handles burst traffic without losing messages", %{
    source_queue: source_queue,
    baseline: baseline
  } do
    burst_count = 1_000

    # Send all messages at once (burst)
    for i <- 1..burst_count do
      MemoryProducer.push_message(source_queue, %{
        "id" => i,
        "burst" => true,
        "value" => :rand.uniform(100)
      })
    end

    # Verify all get processed
    wait_for_processing(burst_count, baseline, 15_000)

    snapshot = Metrics.snapshot()
    processed_in_test = snapshot.processed_total - baseline
    assert processed_in_test >= burst_count
  end

  defp wait_for_processing(expected_count, baseline, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait(expected_count, baseline, deadline)
  end

  defp do_wait(expected, baseline, deadline) do
    now = System.monotonic_time(:millisecond)

    if now > deadline do
      snapshot = Metrics.snapshot()
      processed = snapshot.processed_total - baseline

      flunk(
        "Timeout waiting for #{expected} messages. Processed: #{processed}, " <>
          "Failed: #{snapshot.failed_total}, Skipped: #{snapshot.skipped_total}"
      )
    end

    snapshot = Metrics.snapshot()
    processed = snapshot.processed_total - baseline

    if processed >= expected do
      :ok
    else
      Process.sleep(100)
      do_wait(expected, baseline, deadline)
    end
  end
end
