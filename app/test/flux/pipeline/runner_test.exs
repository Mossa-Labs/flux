defmodule Flux.Pipeline.RunnerTest do
  use Flux.DataCase, async: false

  import Flux.AccountsFixtures
  import Flux.PipelinesFixtures

  alias Broadway.Message
  alias Flux.Pipeline.Runner
  alias Flux.Queue.Adapters.Memory

  setup do
    Memory.clear()
    scope = user_scope_fixture()
    %{org_id: scope.organization_id}
  end

  # Attaches a telemetry handler that forwards matching events to the test
  # process, detaching automatically when the test ends.
  defp attach_telemetry(events) do
    ref = make_ref()
    test_pid = self()

    :telemetry.attach_many(
      "runner-test-#{inspect(ref)}",
      events,
      fn event, measurements, metadata, _ ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach("runner-test-#{inspect(ref)}") end)
    ref
  end

  defp context(overrides) do
    Enum.into(overrides, %{
      pipeline_id: 1,
      version: 1,
      steps: %{},
      destination_queue: nil,
      sink_ids: []
    })
  end

  defp message(data), do: %Message{data: data, acknowledger: {__MODULE__, :ack, :ok}}

  # Broadway acknowledger so `ack_immediately/1` in the :skip path has somewhere
  # to go without booting a full pipeline.
  def ack(:ack, _successful, _failed), do: :ok

  describe "handle_message/3 — success path" do
    test "passes through and emits processed telemetry" do
      attach_telemetry([[:flux, :pipeline, :message, :processed]])

      ctx = context(pipeline_id: 42, steps: %{})
      result = Runner.handle_message(:default, message(%{"a" => 1}), ctx)

      assert result.data == %{"a" => 1}
      assert_receive {:telemetry, [:flux, :pipeline, :message, :processed], %{count: 1}, meta}
      assert meta.pipeline_id == 42
    end

    test "publishes transformed data to the destination queue" do
      ctx = context(destination_queue: "downstream.queue", steps: %{})
      Runner.handle_message(:default, message(%{"value" => 7}), ctx)

      assert [msg] = Memory.get_messages("downstream.queue")
      assert msg.payload == %{"value" => 7}
      assert msg.source == "pipeline"
    end

    test "does not publish when destination queue is nil or empty" do
      Runner.handle_message(:default, message(%{"x" => 1}), context(destination_queue: nil))
      Runner.handle_message(:default, message(%{"x" => 1}), context(destination_queue: ""))

      assert Memory.get_messages("") == []
    end

    test "does not fan out to sinks when sink_ids is empty" do
      # No sinks configured → deliver_to_sinks/3 is a no-op and the message
      # still completes successfully.
      result = Runner.handle_message(:default, message(%{"ok" => true}), context(sink_ids: []))
      assert result.data == %{"ok" => true}
    end
  end

  describe "handle_message/3 — skip path" do
    test "nils the data and emits skipped telemetry" do
      attach_telemetry([[:flux, :pipeline, :message, :skipped]])

      # A filter step whose condition does not match yields {:skip, _}.
      steps = %{
        "version" => "1.0",
        "steps" => [
          %{
            "id" => "f1",
            "type" => "native",
            "operation" => "filter",
            "config" => %{"field" => "keep", "operator" => "eq", "value" => true}
          }
        ]
      }

      ctx = context(pipeline_id: 7, steps: steps)
      result = Runner.handle_message(:default, message(%{"keep" => false}), ctx)

      assert result.data == nil
      assert_receive {:telemetry, [:flux, :pipeline, :message, :skipped], %{count: 1}, meta}
      assert meta.pipeline_id == 7
    end
  end

  describe "handle_message/3 — error path" do
    test "marks the message failed and emits failed telemetry" do
      attach_telemetry([[:flux, :pipeline, :message, :failed]])

      # An invalid step IR makes the Interpreter return {:error, _}.
      steps = %{"version" => "1.0", "steps" => [%{"type" => "bogus"}]}
      ctx = context(pipeline_id: 9, steps: steps)

      result = Runner.handle_message(:default, message(%{"a" => 1}), ctx)

      assert result.status != :ok
      assert_receive {:telemetry, [:flux, :pipeline, :message, :failed], %{count: 1}, meta}
      assert meta.pipeline_id == 9
    end
  end

  describe "handle_message/3 — data parsing" do
    test "decodes a JSON string payload" do
      ctx = context(destination_queue: "parsed.queue")
      Runner.handle_message(:default, message(~s({"n":1})), ctx)

      assert [msg] = Memory.get_messages("parsed.queue")
      assert msg.payload == %{"n" => 1}
    end

    test "wraps an undecodable string under \"raw\"" do
      ctx = context(destination_queue: "raw.queue")
      Runner.handle_message(:default, message("not json"), ctx)

      assert [msg] = Memory.get_messages("raw.queue")
      assert msg.payload == %{"raw" => "not json"}
    end

    test "wraps a non-binary, non-map payload under \"raw\"" do
      ctx = context(destination_queue: "list.queue")
      Runner.handle_message(:default, message([1, 2, 3]), ctx)

      assert [msg] = Memory.get_messages("list.queue")
      assert msg.payload == %{"raw" => [1, 2, 3]}
    end
  end

  describe "handle_failed/2" do
    test "emits batch failed telemetry and returns the messages unchanged" do
      attach_telemetry([[:flux, :pipeline, :batch, :failed]])

      messages = [message(%{"a" => 1}), message(%{"b" => 2})]
      assert ^messages = Runner.handle_failed(messages, %{pipeline_id: 3})

      assert_receive {:telemetry, [:flux, :pipeline, :batch, :failed], %{count: 2}, meta}
      assert meta.pipeline_id == 3
    end
  end

  describe "start_link/1 (Broadway boot)" do
    test "starts a runner and processes a pushed message through the memory producer",
         %{org_id: org_id} do
      attach_telemetry([[:flux, :pipeline, :message, :processed]])

      # Steps include a source node (exercises source-config extraction) and an
      # anomaly step (exercises the configure_detector/1 path + mode-param parsing).
      steps = %{
        "version" => "1.0",
        "nodes" => [
          %{
            "type" => "source",
            "sourceConfig" => %{"queue" => "boot.source", "prefetchCount" => 10}
          }
        ],
        "steps" => [
          %{
            "id" => "ai1",
            "type" => "ai",
            "operation" => "anomaly_detect",
            "config" => %{"mode" => "seasonal", "fields" => "amount, count", "period" => 7}
          }
        ]
      }

      pipeline =
        pipeline_fixture(org_id, %{source_queue: "boot.source", steps: steps})

      pid = start_supervised!({Runner, pipeline})
      assert is_pid(pid)

      Flux.Pipeline.Producers.Memory.push_message("boot.source", %{"amount" => 5})

      assert_receive {:telemetry, [:flux, :pipeline, :message, :processed], _, _}, 2_000
    end
  end
end
