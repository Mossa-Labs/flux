defmodule Flux.Workers.PollerTest do
  use Flux.DataCase, async: false
  use Oban.Testing, repo: Flux.Repo

  alias Flux.Workers.Poller
  alias Flux.Queue.Adapters.Memory

  setup do
    Memory.clear()
    :ok
  end

  describe "perform/1" do
    test "publishes fetched data to queue (placeholder data)" do
      # Test with no URL (placeholder data)
      args = %{"source_id" => "test-source"}

      assert :ok = perform_job(Poller, args)

      messages = Memory.get_messages("polling.test-source")
      assert length(messages) == 1

      [message] = messages
      assert message.source == "poller:test-source"
      assert message.metadata.poll_type == "scheduled"
      assert message.payload.placeholder == true
    end

    test "includes polled_at timestamp in metadata" do
      args = %{"source_id" => "timestamp-test"}

      assert :ok = perform_job(Poller, args)

      [message] = Memory.get_messages("polling.timestamp-test")
      assert is_binary(message.metadata.polled_at)
    end

    test "job has unique constraint" do
      args = %{"source_id" => "unique-test"}

      assert {:ok, %Oban.Job{conflict?: false}} = Oban.insert(Poller.new(args))
      assert {:ok, %Oban.Job{conflict?: true}} = Oban.insert(Poller.new(args))
    end

    test "job is configured for polling queue" do
      args = %{"source_id" => "queue-test"}
      changeset = Poller.new(args)

      assert Ecto.Changeset.get_field(changeset, :queue) == "polling"
    end

    test "job has max 3 attempts" do
      args = %{"source_id" => "attempts-test"}
      changeset = Poller.new(args)

      assert Ecto.Changeset.get_field(changeset, :max_attempts) == 3
    end

    test "sets the poller source and scheduled poll_type metadata" do
      assert :ok = perform_job(Poller, %{"source_id" => "meta-src"})

      [message] = Memory.get_messages("polling.meta-src")
      assert message.source == "poller:meta-src"
      assert message.metadata.poll_type == "scheduled"
    end

    # NOTE: the URL-fetch branches of fetch_data/2 (2xx success, non-2xx error,
    # transport error) are not unit-tested here — exercising them deterministically
    # needs an HTTP stub (Bypass / a Req.Test plug), which is not yet a project
    # dependency. They remain covered by manual/integration testing.
  end
end
