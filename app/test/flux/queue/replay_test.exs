defmodule Flux.Queue.ReplayTest do
  use Flux.DataCase, async: true
  use Oban.Testing, repo: Flux.Repo

  import Flux.AccountsFixtures
  import Flux.StructureFixtures
  import Flux.PipelinesFixtures

  alias Flux.Queue.Replay
  alias Flux.Workers.ReplayWorker

  describe "normalize_filters/2" do
    test "passes queue and source through, dropping blanks" do
      assert {:ok, normalized} =
               Replay.normalize_filters(
                 %{"queue" => "events.github", "source" => "webhook", "extra" => ""},
                 1
               )

      assert normalized == %{"queue" => "events.github", "source" => "webhook"}
    end

    test "returns an empty map for blank filters" do
      assert {:ok, %{}} = Replay.normalize_filters(%{"queue" => "", "source" => "  "}, 1)
    end

    test "normalizes a DateTime time_range to ISO8601 strings" do
      from = ~U[2026-06-01 00:00:00Z]
      to = ~U[2026-06-02 00:00:00Z]

      assert {:ok, %{"time_range" => %{"from" => f, "to" => t}}} =
               Replay.normalize_filters(%{time_range: %{from: from, to: to}}, 1)

      assert f == DateTime.to_iso8601(from)
      assert t == DateTime.to_iso8601(to)
    end

    test "drops a partial time_range" do
      assert {:ok, normalized} =
               Replay.normalize_filters(%{time_range: %{from: ~U[2026-06-01 00:00:00Z]}}, 1)

      refute Map.has_key?(normalized, "time_range")
    end

    test "resolves pipeline_id to its source_queue" do
      scope = user_scope_fixture()
      org = organization_fixture(scope)
      pipeline = pipeline_fixture(org.id, %{source_queue: "events.orders"})

      assert {:ok, %{"queue" => "events.orders"}} =
               Replay.normalize_filters(%{"pipeline_id" => pipeline.id}, org.id)
    end

    test "returns an error for an unknown pipeline_id" do
      assert {:error, :pipeline_not_found} =
               Replay.normalize_filters(%{"pipeline_id" => 999_999}, 1)
    end
  end

  describe "replay_messages/2" do
    test "enqueues a ReplayWorker job with normalized filters" do
      assert {:ok, _job} = Replay.replay_messages(%{"queue" => "events.x"}, organization_id: 7)

      assert_enqueued(
        worker: ReplayWorker,
        args: %{
          "organization_id" => 7,
          "filters" => %{"queue" => "events.x"},
          "batch_size" => 100
        }
      )
    end

    test "propagates a pipeline resolution error instead of enqueuing" do
      assert {:error, :pipeline_not_found} =
               Replay.replay_messages(%{"pipeline_id" => 123_456}, organization_id: 7)

      refute_enqueued(worker: ReplayWorker)
    end
  end
end
