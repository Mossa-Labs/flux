defmodule Flux.PipelinesTest do
  use Flux.DataCase

  alias Flux.Pipelines
  alias Flux.Pipelines.Pipeline

  import Flux.AccountsFixtures
  import Flux.PipelinesFixtures
  import Flux.StructureFixtures

  setup do
    scope = user_scope_fixture()
    %{org_id: scope.organization_id, scope: scope}
  end

  describe "list_pipelines/1" do
    test "returns all pipelines for the organization", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id)
      assert pipeline in Pipelines.list_pipelines(org_id)
    end

    test "does not return pipelines from other organizations", %{org_id: org_id, scope: scope} do
      other_org = organization_fixture(scope)
      _other_pipeline = pipeline_fixture(other_org.id)

      pipelines = Pipelines.list_pipelines(org_id)
      assert Enum.all?(pipelines, &(&1.organization_id == org_id))
    end

    test "returns pipelines ordered by updated_at desc", %{org_id: org_id} do
      _p1 = pipeline_fixture(org_id, %{name: "first"})
      _p2 = pipeline_fixture(org_id, %{name: "second"})

      pipelines = Pipelines.list_pipelines(org_id)
      assert length(pipelines) >= 2

      timestamps = Enum.map(pipelines, & &1.updated_at)
      assert timestamps == Enum.sort(timestamps, {:desc, DateTime})
    end

    test "returns empty list when no pipelines exist", %{scope: scope} do
      other_org = organization_fixture(scope)
      assert Pipelines.list_pipelines(other_org.id) == []
    end
  end

  describe "list_active_pipelines/0" do
    test "returns only active pipelines", %{org_id: org_id} do
      active = pipeline_fixture(org_id, %{status: "active"})
      _paused = pipeline_fixture(org_id, %{status: "paused"})
      _stopped = pipeline_fixture(org_id, %{status: "stopped"})

      actives = Pipelines.list_active_pipelines()
      assert active in actives
      assert Enum.all?(actives, &(&1.status == "active"))
    end

    test "returns empty list when no active pipelines exist", %{org_id: org_id} do
      _stopped = pipeline_fixture(org_id, %{status: "stopped"})

      actives = Pipelines.list_active_pipelines()
      refute Enum.any?(actives, &(&1.organization_id == org_id))
    end
  end

  describe "get_pipeline!/1" do
    test "returns the pipeline with given id", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id)
      assert %Pipeline{} = fetched = Pipelines.get_pipeline!(pipeline.id)
      assert fetched.id == pipeline.id
    end

    test "raises if pipeline does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Pipelines.get_pipeline!(-1)
      end
    end
  end

  describe "get_pipeline/2" do
    test "returns the pipeline scoped by organization", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id)
      assert %Pipeline{} = Pipelines.get_pipeline(pipeline.id, org_id)
    end

    test "returns nil when pipeline belongs to different organization", %{
      org_id: org_id,
      scope: scope
    } do
      other_org = organization_fixture(scope)
      pipeline = pipeline_fixture(other_org.id)
      assert is_nil(Pipelines.get_pipeline(pipeline.id, org_id))
    end

    test "returns nil when pipeline does not exist", %{org_id: org_id} do
      assert is_nil(Pipelines.get_pipeline(-1, org_id))
    end
  end

  describe "create_pipeline/1" do
    test "with valid data creates a pipeline", %{org_id: org_id} do
      attrs = %{
        name: "my-pipeline",
        source_queue: "events.inbound",
        organization_id: org_id,
        steps: %{"version" => "1.0", "steps" => []}
      }

      assert {:ok, %Pipeline{} = pipeline} = Pipelines.create_pipeline(attrs)
      assert pipeline.name == "my-pipeline"
      assert pipeline.source_queue == "events.inbound"
      assert pipeline.status == "stopped"
      assert pipeline.organization_id == org_id
    end

    test "requires name", %{org_id: org_id} do
      attrs = %{source_queue: "q", organization_id: org_id}
      {:error, changeset} = Pipelines.create_pipeline(attrs)
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires source_queue", %{org_id: org_id} do
      attrs = %{name: "p", organization_id: org_id}
      {:error, changeset} = Pipelines.create_pipeline(attrs)
      assert %{source_queue: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires organization_id" do
      attrs = %{name: "p", source_queue: "q"}
      {:error, changeset} = Pipelines.create_pipeline(attrs)
      assert %{organization_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "enforces unique name within organization", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id)

      attrs = %{
        name: pipeline.name,
        source_queue: "other.queue",
        organization_id: org_id
      }

      assert {:error, changeset} = Pipelines.create_pipeline(attrs)
      # The org-scoped uniqueness must read as a name conflict, not the confusing
      # "Organization has already been taken".
      assert %{name: ["is already used by another pipeline"]} = errors_on(changeset)
      refute Map.has_key?(errors_on(changeset), :organization_id)
    end

    test "allows duplicate name across different organizations", %{org_id: org_id, scope: scope} do
      pipeline = pipeline_fixture(org_id)
      other_org = organization_fixture(scope)

      attrs = %{
        name: pipeline.name,
        source_queue: "other.queue",
        organization_id: other_org.id
      }

      assert {:ok, %Pipeline{}} = Pipelines.create_pipeline(attrs)
    end

    test "validates status inclusion", %{org_id: org_id} do
      attrs = %{name: "p", source_queue: "q", organization_id: org_id, status: "invalid"}
      {:error, changeset} = Pipelines.create_pipeline(attrs)
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "rejects non-map steps value", %{org_id: org_id} do
      attrs = %{
        name: "p",
        source_queue: "q",
        organization_id: org_id,
        steps: "not-a-map"
      }

      {:error, changeset} = Pipelines.create_pipeline(attrs)
      assert %{steps: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts valid steps format", %{org_id: org_id} do
      attrs = %{
        name: "with-steps",
        source_queue: "q",
        organization_id: org_id,
        steps: %{"version" => "1.0", "steps" => [%{"type" => "filter"}]}
      }

      assert {:ok, %Pipeline{} = pipeline} = Pipelines.create_pipeline(attrs)
      assert pipeline.steps == %{"version" => "1.0", "steps" => [%{"type" => "filter"}]}
    end

    test "defaults status to stopped", %{org_id: org_id} do
      attrs = %{name: "p", source_queue: "q", organization_id: org_id}
      assert {:ok, %Pipeline{status: "stopped"}} = Pipelines.create_pipeline(attrs)
    end

    test "defaults config to empty map", %{org_id: org_id} do
      attrs = %{name: "p", source_queue: "q", organization_id: org_id}
      assert {:ok, %Pipeline{config: %{}}} = Pipelines.create_pipeline(attrs)
    end

    test "defaults sink_ids to empty list", %{org_id: org_id} do
      attrs = %{name: "p", source_queue: "q", organization_id: org_id}
      assert {:ok, %Pipeline{sink_ids: []}} = Pipelines.create_pipeline(attrs)
    end
  end

  describe "update_pipeline/2" do
    test "with valid data updates the pipeline", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id)
      attrs = %{name: "updated-name", description: "updated desc"}

      assert {:ok, %Pipeline{} = updated} = Pipelines.update_pipeline(pipeline, attrs)
      assert updated.name == "updated-name"
      assert updated.description == "updated desc"
    end

    test "with invalid data returns error changeset", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id)
      assert {:error, %Ecto.Changeset{}} = Pipelines.update_pipeline(pipeline, %{name: nil})
      assert pipeline == Pipelines.get_pipeline!(pipeline.id)
    end
  end

  describe "update_status/2" do
    test "updates to active", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id, %{status: "stopped"})
      assert {:ok, %Pipeline{status: "active"}} = Pipelines.update_status(pipeline, "active")
    end

    test "updates to paused", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id, %{status: "active"})
      assert {:ok, %Pipeline{status: "paused"}} = Pipelines.update_status(pipeline, "paused")
    end

    test "updates to stopped", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id, %{status: "active"})
      assert {:ok, %Pipeline{status: "stopped"}} = Pipelines.update_status(pipeline, "stopped")
    end

    test "raises on invalid status", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id)

      assert_raise FunctionClauseError, fn ->
        Pipelines.update_status(pipeline, "invalid")
      end
    end
  end

  describe "delete_pipeline/1" do
    test "deletes the pipeline", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id)
      assert {:ok, %Pipeline{}} = Pipelines.delete_pipeline(pipeline)

      assert_raise Ecto.NoResultsError, fn ->
        Pipelines.get_pipeline!(pipeline.id)
      end
    end
  end

  describe "change_pipeline/2" do
    test "returns a changeset", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id)
      assert %Ecto.Changeset{} = Pipelines.change_pipeline(pipeline)
    end

    test "returns a changeset with attrs applied", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id)
      changeset = Pipelines.change_pipeline(pipeline, %{name: "new-name"})
      assert %Ecto.Changeset{} = changeset
      assert get_change(changeset, :name) == "new-name"
    end
  end
end
