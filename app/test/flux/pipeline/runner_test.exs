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

  # The organization a bare handle_message/3 context runs as. Tests that touch
  # the database (sinks) pass a real organization instead.
  @org_id 4242

  defp context(overrides) do
    Enum.into(overrides, %{
      pipeline_id: 1,
      organization_id: @org_id,
      version: 1,
      steps: %{},
      destination_queue: nil,
      sink_ids: [],
      queue_adapter: Memory
    })
  end

  # A consumed message, tagged by the Memory producer with the organization it
  # was published for.
  defp message(data, org_id \\ @org_id) do
    %Message{
      data: data,
      metadata: %{organization_id: org_id},
      acknowledger: {__MODULE__, :ack, :ok}
    }
  end

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

      assert [msg] = Memory.get_messages(@org_id, "downstream.queue")
      assert msg.payload == %{"value" => 7}
      assert msg.source == "pipeline"
      assert msg.organization_id == @org_id
    end

    test "does not publish when destination queue is nil or empty" do
      Runner.handle_message(:default, message(%{"x" => 1}), context(destination_queue: nil))
      Runner.handle_message(:default, message(%{"x" => 1}), context(destination_queue: ""))

      assert :sys.get_state(Memory).queues == %{}
    end

    test "does not fan out to sinks when sink_ids is empty" do
      # No sinks configured → deliver_to_sinks/3 is a no-op and the message
      # still completes successfully.
      result = Runner.handle_message(:default, message(%{"ok" => true}), context(sink_ids: []))
      assert result.data == %{"ok" => true}
    end

    test "delivers to a Parquet sink buffered per sink and pipeline", %{org_id: org_id} do
      alias Flux.Sink.Adapters.Parquet

      directory = "runner-test-#{System.unique_integer([:positive])}"
      root = Path.join(Parquet.Paths.base_dir(), directory)
      on_exit(fn -> File.rm_rf!(root) end)

      sink =
        Flux.SinksFixtures.sink_fixture(org_id, %{
          type: "parquet",
          config: %{"directory" => directory}
        })

      on_exit(fn -> Parquet.Supervisor.stop_buffer({sink.id, 1}) end)
      attach_telemetry([[:flux, :sink, :delivered]])
      sink_id = sink.id

      for i <- 1..3 do
        Runner.handle_message(
          :default,
          message(%{"i" => i}, org_id),
          context(sink_ids: [sink.id], organization_id: org_id)
        )
      end

      for _ <- 1..3 do
        assert_receive {:telemetry, [:flux, :sink, :delivered], _,
                        %{sink_id: ^sink_id, pipeline_id: 1}}
      end

      {:ok, pid} = Parquet.Supervisor.buffer({sink.id, 1}, %{})
      :ok = Parquet.Buffer.flush(pid)

      assert [file] = root |> Path.join("1/*.parquet") |> Path.wildcard()
      rows = file |> Explorer.DataFrame.from_parquet!() |> Explorer.DataFrame.to_columns()
      assert Enum.sort(rows["i"]) == [1, 2, 3]
    end

    # Defence in depth: even if a foreign sink id already sits in a pipeline row
    # (written before sinks were checked), the runner must not deliver to it.
    test "never delivers to another organization's sink", %{org_id: org_id} do
      alias Flux.Sink.Adapters.Parquet

      other_org_id =
        Flux.Repo.insert!(%Flux.Structure.Organization{
          name: "Other",
          slug: "other-#{System.unique_integer([:positive])}"
        }).id

      directory = "runner-test-#{System.unique_integer([:positive])}"
      root = Path.join(Parquet.Paths.base_dir(), directory)
      on_exit(fn -> File.rm_rf!(root) end)

      foreign =
        Flux.SinksFixtures.sink_fixture(other_org_id, %{
          type: "parquet",
          config: %{"directory" => directory}
        })

      on_exit(fn -> Parquet.Supervisor.stop_buffer({foreign.id, 1}) end)
      attach_telemetry([[:flux, :sink, :delivered]])

      Runner.handle_message(
        :default,
        message(%{"i" => 1}, org_id),
        context(sink_ids: [foreign.id], organization_id: org_id)
      )

      refute_receive {:telemetry, [:flux, :sink, :delivered], _, _}, 200
    end
  end

  describe "handle_message/3 — organization check" do
    test "drops a message published for another organization" do
      attach_telemetry([
        [:flux, :pipeline, :message, :refused],
        [:flux, :pipeline, :message, :processed]
      ])

      ctx = context(pipeline_id: 11, destination_queue: "out")
      result = Runner.handle_message(:default, message(%{"secret" => 1}, 9999), ctx)

      assert result.data == nil
      assert result.status == :ok

      assert_receive {:telemetry, [:flux, :pipeline, :message, :refused], %{count: 1}, meta}
      assert meta == %{pipeline_id: 11, organization_id: @org_id, reason: :organization_mismatch}
      refute_receive {:telemetry, [:flux, :pipeline, :message, :processed], _, _}, 50
      assert Memory.get_messages(@org_id, "out") == []
    end

    test "drops a message that carries no organization" do
      attach_telemetry([[:flux, :pipeline, :message, :refused]])

      no_org = %Message{data: %{"a" => 1}, acknowledger: {__MODULE__, :ack, :ok}}
      result = Runner.handle_message(:default, no_org, context(pipeline_id: 12))

      assert result.data == nil
      assert_receive {:telemetry, [:flux, :pipeline, :message, :refused], _, meta}
      assert meta.reason == :missing_organization
    end

    test "drops every message when the context names no queue adapter" do
      attach_telemetry([[:flux, :pipeline, :message, :refused]])

      ctx = Map.delete(context(pipeline_id: 13), :queue_adapter)
      result = Runner.handle_message(:default, message(%{"a" => 1}), ctx)

      assert result.data == nil
      assert_receive {:telemetry, [:flux, :pipeline, :message, :refused], _, meta}
      assert meta.reason == :missing_organization
    end

    test "never logs the refused payload" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          Runner.handle_message(:default, message(%{"card" => "4242-SECRET"}, 9999), context([]))
        end)

      assert log =~ "refused a message: organization_mismatch"
      refute log =~ "4242-SECRET"
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

      assert [msg] = Memory.get_messages(@org_id, "parsed.queue")
      assert msg.payload == %{"n" => 1}
    end

    test "wraps an undecodable string under \"raw\"" do
      ctx = context(destination_queue: "raw.queue")
      Runner.handle_message(:default, message("not json"), ctx)

      assert [msg] = Memory.get_messages(@org_id, "raw.queue")
      assert msg.payload == %{"raw" => "not json"}
    end

    test "wraps a non-binary, non-map payload under \"raw\"" do
      ctx = context(destination_queue: "list.queue")
      Runner.handle_message(:default, message([1, 2, 3]), ctx)

      assert [msg] = Memory.get_messages(@org_id, "list.queue")
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

      Flux.Pipeline.Producers.Memory.push_message(org_id, "boot.source", %{"amount" => 5})

      assert_receive {:telemetry, [:flux, :pipeline, :message, :processed], _, _}, 2_000
    end

    test "consumes the derived source_queue when the source node has no explicit queue",
         %{org_id: org_id} do
      attach_telemetry([[:flux, :pipeline, :message, :processed]])

      # A webhook source node carries no "queue" key. The builder derives and
      # persists `webhooks.<path>` into source_queue; the runner must fall back
      # to it (rather than the shared "default" queue) and consume from there.
      steps = %{
        "version" => "1.0",
        "nodes" => [
          %{
            "type" => "source",
            "sourceConfig" => %{"type" => "webhook", "webhookPath" => "github"}
          }
        ]
      }

      pipeline =
        pipeline_fixture(org_id, %{source_queue: "webhooks.github", steps: steps})

      start_supervised!({Runner, pipeline})
      Flux.Pipeline.Producers.Memory.push_message(org_id, "webhooks.github", %{"event" => "push"})

      assert_receive {:telemetry, [:flux, :pipeline, :message, :processed], _, _}, 2_000
    end

    test "consumes only its own organization's queue", %{org_id: org_id} do
      attach_telemetry([[:flux, :pipeline, :message, :processed]])

      pipeline = pipeline_fixture(org_id, %{source_queue: "webhooks.github"})
      start_supervised!({Runner, pipeline})

      other_org_id =
        Flux.Repo.insert!(%Flux.Structure.Organization{
          name: "Other",
          slug: "other-#{System.unique_integer([:positive])}"
        }).id

      Flux.Pipeline.Producers.Memory.push_message(other_org_id, "webhooks.github", %{"x" => 1})
      refute_receive {:telemetry, [:flux, :pipeline, :message, :processed], _, _}, 200
    end

    # A row written before queue names were checked: the runner refuses to
    # start rather than consume or publish outside the organization.
    test "refuses to start on a queue name outside the organization", %{org_id: org_id} do
      base = %Flux.Pipelines.Pipeline{
        id: System.unique_integer([:positive]),
        organization_id: org_id,
        source_queue: "webhooks.github",
        config: %{},
        steps: %{"version" => "1.0", "steps" => []},
        sink_ids: []
      }

      assert {:error, {:source_queue, {:invalid_queue, :reserved_prefix}}} =
               Runner.start_link(%{base | source_queue: "org.1.webhooks.github"})

      assert {:error, {:destination_queue, {:invalid_queue, :reserved_prefix}}} =
               Runner.start_link(%{base | destination_queue: "flux.events"})

      assert {:error, {:source_queue, :organization_required}} =
               Runner.start_link(%{base | organization_id: nil})
    end
  end
end
