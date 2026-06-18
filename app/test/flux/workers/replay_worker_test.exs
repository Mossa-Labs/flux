defmodule Flux.Workers.ReplayWorkerTest.FakeAdapter do
  @moduledoc """
  Test double implementing the DLQ-replay slice of `Flux.Queue.Adapter`. Batch
  results are scripted via an `Agent`; `replay_dlq/2` pops the next one per call,
  letting tests drive the worker's batch loop. An `{:error, reason}` element in
  the batch list is returned verbatim to exercise the failure path.
  """
  @behaviour Flux.Queue.Adapter

  def start(batches, depth) do
    Agent.start_link(fn -> %{batches: batches, depth: depth} end, name: __MODULE__)
  end

  @impl true
  def get_dlq_depth, do: {:ok, Agent.get(__MODULE__, & &1.depth)}

  @impl true
  def replay_dlq(_filters, _limit) do
    Agent.get_and_update(__MODULE__, fn
      %{batches: [{:error, _} = error | rest]} = state -> {error, %{state | batches: rest}}
      %{batches: [batch | rest]} = state -> {{:ok, batch}, %{state | batches: rest}}
      %{batches: []} = state -> {{:ok, %{replayed: 0, skipped: 0, exhausted?: true}}, state}
    end)
  end

  @impl true
  def publish(_queue, _message, _opts), do: :ok

  @impl true
  def ack(_message), do: :ok

  @impl true
  def reject(_message, _requeue), do: :ok
end

defmodule Flux.Workers.ReplayWorkerTest do
  use Flux.DataCase, async: false
  use Oban.Testing, repo: Flux.Repo

  alias Flux.Queue.Registry
  alias Flux.Queue.Replay
  alias Flux.Workers.ReplayWorker
  alias Flux.Workers.ReplayWorkerTest.FakeAdapter

  setup do
    Registry.register("fake_replay", FakeAdapter)
    Registry.set_active("fake_replay")
    on_exit(fn -> Registry.set_active("memory") end)
    :ok
  end

  defp start_fake(batches, depth) do
    start_supervised!(%{id: FakeAdapter, start: {FakeAdapter, :start, [batches, depth]}})
  end

  test "loops replay_dlq until exhausted, accumulating progress and broadcasting" do
    start_fake(
      [
        %{replayed: 3, skipped: 1, exhausted?: false},
        %{replayed: 2, skipped: 0, exhausted?: true}
      ],
      10
    )

    Phoenix.PubSub.subscribe(Flux.PubSub, Replay.topic(1))

    assert :ok =
             ReplayWorker.perform(%Oban.Job{
               id: 1,
               args: %{"organization_id" => 1, "filters" => %{}, "batch_size" => 5}
             })

    assert_receive {:replay_progress, %{processed: 3, skipped: 1, failed: 0}}
    assert_receive {:replay_progress, %{processed: 5, skipped: 1, failed: 0, total: total}}
    assert total >= 5
    assert_receive {:replay_done, %{processed: 5, skipped: 1, failed: 0}}
  end

  test "counts a failure and stops when a batch errors" do
    start_fake([{:error, :not_connected}], 5)

    Phoenix.PubSub.subscribe(Flux.PubSub, Replay.topic(2))

    assert :ok =
             ReplayWorker.perform(%Oban.Job{
               id: 2,
               args: %{"organization_id" => 1, "filters" => %{}, "batch_size" => 5}
             })

    assert_receive {:replay_done, %{failed: 1, processed: 0}}
  end

  test "completes without a configured organization (record_event skipped)" do
    start_fake([%{replayed: 1, skipped: 0, exhausted?: true}], 1)

    assert :ok =
             ReplayWorker.perform(%Oban.Job{
               id: 3,
               args: %{"organization_id" => nil, "filters" => %{}, "batch_size" => 5}
             })
  end
end
