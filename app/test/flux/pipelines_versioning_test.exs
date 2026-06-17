defmodule Flux.PipelinesVersioningTest do
  use Flux.DataCase

  alias Flux.Pipelines

  import Flux.AccountsFixtures
  import Flux.PipelinesFixtures

  setup do
    scope = user_scope_fixture()
    %{org_id: scope.organization_id, actor_id: scope.user.id}
  end

  defp steps_with(steps), do: %{"version" => "1.0", "steps" => steps}

  defp filter_step(extra \\ %{}),
    do: %{"type" => "native", "operation" => "filter", "config" => extra}

  describe "create_pipeline/2" do
    test "records version 1 and sets current_version", %{org_id: org_id, actor_id: actor_id} do
      {:ok, pipeline} =
        Pipelines.create_pipeline(
          %{name: "p1", source_queue: "q", organization_id: org_id, steps: steps_with([])},
          actor_id: actor_id
        )

      assert pipeline.current_version == 1

      assert [version] = Pipelines.list_pipeline_versions(pipeline.id)
      assert version.version == 1
      assert version.change_summary == "Created pipeline"
      assert version.created_by == actor_id
      assert version.name == "p1"
    end
  end

  describe "update_pipeline/3 versioning" do
    test "a config change creates a new version and advances current_version", %{
      org_id: org_id,
      actor_id: actor_id
    } do
      pipeline = pipeline_fixture(org_id)

      {:ok, updated} =
        Pipelines.update_pipeline(pipeline, %{steps: steps_with([filter_step()])},
          actor_id: actor_id
        )

      assert updated.current_version == 2
      versions = Pipelines.list_pipeline_versions(pipeline.id)
      assert Enum.map(versions, & &1.version) == [2, 1]
      assert hd(versions).change_summary == "Added filter step"
    end

    test "a rename produces a 'Renamed pipeline' summary", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id)
      {:ok, updated} = Pipelines.update_pipeline(pipeline, %{name: "renamed"})
      assert updated.current_version == 2

      assert hd(Pipelines.list_pipeline_versions(pipeline.id)).change_summary ==
               "Renamed pipeline"
    end

    test "an unchanged save creates no new version", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id)
      {:ok, _} = Pipelines.update_pipeline(pipeline, %{name: pipeline.name})
      assert length(Pipelines.list_pipeline_versions(pipeline.id)) == 1
    end

    test "update_status creates no version", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id)
      before = Pipelines.list_pipeline_versions(pipeline.id)

      {:ok, updated} = Pipelines.update_status(pipeline, "active")

      assert updated.status == "active"
      assert updated.current_version == pipeline.current_version
      assert Pipelines.list_pipeline_versions(pipeline.id) == before
    end

    test "prunes to the most recent 50 versions", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id)

      pipeline =
        Enum.reduce(1..60, pipeline, fn i, p ->
          {:ok, p} =
            Pipelines.update_pipeline(p, %{steps: steps_with([filter_step(%{"n" => i})])})

          p
        end)

      versions = Pipelines.list_pipeline_versions(pipeline.id)
      numbers = Enum.map(versions, & &1.version)

      assert length(versions) == 50
      assert Enum.max(numbers) == pipeline.current_version
      assert Enum.min(numbers) == pipeline.current_version - 49
    end
  end

  describe "rollback_pipeline/3" do
    test "is non-destructive and restores the snapshot", %{org_id: org_id, actor_id: actor_id} do
      pipeline = pipeline_fixture(org_id, %{name: "orig"})
      {:ok, v2} = Pipelines.update_pipeline(pipeline, %{steps: steps_with([filter_step()])})

      {:ok, rolled} = Pipelines.rollback_pipeline(v2, 1, actor_id: actor_id)

      # New version entry, history preserved (1, 2, 3 all present).
      assert rolled.current_version == 3
      assert Enum.map(Pipelines.list_pipeline_versions(pipeline.id), & &1.version) == [3, 2, 1]

      # Config matches version 1's snapshot (empty steps), not v2's filter step.
      assert rolled.steps == pipeline.steps

      assert hd(Pipelines.list_pipeline_versions(pipeline.id)).change_summary ==
               "Rolled back to version 1"
    end

    test "returns an error for an unknown version", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id)
      assert {:error, :version_not_found} = Pipelines.rollback_pipeline(pipeline, 99)
    end
  end

  describe "set_running_version/2" do
    test "updates only running_version and creates no version", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id)

      {:ok, updated} = Pipelines.set_running_version(pipeline, 1)
      assert updated.running_version == 1
      assert length(Pipelines.list_pipeline_versions(pipeline.id)) == 1

      {:ok, cleared} = Pipelines.set_running_version(updated, nil)
      assert cleared.running_version == nil
    end
  end
end
