defmodule Flux.Workers.PollerTest do
  use Flux.DataCase, async: false
  use Oban.Testing, repo: Flux.Repo

  alias Flux.Workers.Poller
  alias Flux.Queue.Adapters.Memory

  setup do
    Memory.clear()

    org =
      Flux.Repo.insert!(%Flux.Structure.Organization{
        name: "Org #{System.unique_integer([:positive])}",
        slug: "org-#{System.unique_integer([:positive])}"
      })

    %{org_id: org.id}
  end

  describe "perform/1" do
    test "publishes fetched data to the organization's queue (placeholder data)", %{
      org_id: org_id
    } do
      # Test with no URL (placeholder data)
      args = %{"source_id" => "test-source", "organization_id" => org_id}

      assert :ok = perform_job(Poller, args)

      messages = Memory.get_messages(org_id, "polling.test-source")
      assert length(messages) == 1

      [message] = messages
      assert message.organization_id == org_id
      assert message.source == "poller:test-source"
      assert message.metadata.poll_type == "scheduled"
      assert message.payload.placeholder == true
    end

    test "includes polled_at timestamp in metadata", %{org_id: org_id} do
      args = %{"source_id" => "timestamp-test", "organization_id" => org_id}

      assert :ok = perform_job(Poller, args)

      [message] = Memory.get_messages(org_id, "polling.timestamp-test")
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

    test "sets the poller source and scheduled poll_type metadata", %{org_id: org_id} do
      assert :ok = perform_job(Poller, %{"source_id" => "meta-src", "organization_id" => org_id})

      [message] = Memory.get_messages(org_id, "polling.meta-src")
      assert message.source == "poller:meta-src"
      assert message.metadata.poll_type == "scheduled"
    end

    test "cancels a job without a valid organization, publishing nothing", %{org_id: org_id} do
      for args <- [
            %{"source_id" => "no-org"},
            %{"source_id" => "no-org", "organization_id" => nil},
            %{"source_id" => "no-org", "organization_id" => "#{org_id}"},
            %{"source_id" => "no-org", "organization_id" => 0}
          ] do
        assert {:cancel, :organization_required} = perform_job(Poller, args)
      end

      assert {:cancel, :organization_not_found} =
               perform_job(Poller, %{
                 "source_id" => "no-org",
                 "organization_id" => org_id + 1_000_000
               })

      assert :sys.get_state(Memory).queues == %{}
    end

    test "cancels a job whose source can't name a queue", %{org_id: org_id} do
      assert {:cancel, {:invalid_queue, :invalid_characters}} =
               perform_job(Poller, %{"source_id" => "has space", "organization_id" => org_id})
    end

    # NOTE: the URL-fetch branches of fetch_data/2 (2xx success, non-2xx error,
    # transport error) are not unit-tested here — exercising them deterministically
    # needs an HTTP stub (Bypass / a Req.Test plug), which is not yet a project
    # dependency. They remain covered by manual/integration testing.
  end
end
