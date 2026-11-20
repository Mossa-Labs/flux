defmodule Flux.Pipelines.PipelineSinkScopeTest do
  use Flux.DataCase, async: true

  import Flux.PipelinesFixtures
  import Flux.SinksFixtures

  alias Flux.Pipelines
  alias Flux.Pipelines.PipelineVersion
  alias Flux.Sinks
  alias Flux.Structure.Organization

  # A pipeline delivers to its sinks with their stored, decrypted credentials,
  # so it must only ever reference sinks of its own organization, however the
  # sink ids reach it: create, update, or a rollback to an older version.

  setup do
    org = org()
    other_org = org()

    %{
      org_id: org.id,
      other_org_id: other_org.id,
      own_sink: sink_fixture(org.id),
      foreign_sink: sink_fixture(other_org.id)
    }
  end

  describe "create_pipeline/2" do
    test "accepts the organization's own sinks", %{org_id: org_id, own_sink: own} do
      assert {:ok, pipeline} = Pipelines.create_pipeline(attrs(org_id, sink_ids: [own.id]))
      assert pipeline.sink_ids == [own.id]
    end

    test "rejects another organization's sink", %{org_id: org_id, foreign_sink: foreign} do
      assert {:error, changeset} =
               Pipelines.create_pipeline(attrs(org_id, sink_ids: [foreign.id]))

      assert %{sink_ids: [_]} = errors_on(changeset)
    end

    test "rejects a sink id that doesn't exist", %{org_id: org_id} do
      assert {:error, changeset} = Pipelines.create_pipeline(attrs(org_id, sink_ids: [-1]))
      assert %{sink_ids: [_]} = errors_on(changeset)
    end
  end

  describe "update_pipeline/3" do
    test "rejects adding another organization's sink", %{
      org_id: org_id,
      own_sink: own,
      foreign_sink: foreign
    } do
      pipeline = pipeline_fixture(org_id, %{sink_ids: [own.id]})

      assert {:error, changeset} =
               Pipelines.update_pipeline(pipeline, %{sink_ids: [own.id, foreign.id]})

      assert %{sink_ids: [_]} = errors_on(changeset)
      assert Repo.reload(pipeline).sink_ids == [own.id]
    end

    test "can't move a pipeline to another organization", %{
      org_id: org_id,
      other_org_id: other_org_id
    } do
      pipeline = pipeline_fixture(org_id)

      assert {:ok, updated} =
               Pipelines.update_pipeline(pipeline, %{
                 organization_id: other_org_id,
                 name: "renamed"
               })

      assert updated.name == "renamed"
      assert Repo.reload(pipeline).organization_id == org_id
    end
  end

  describe "Runner.steps_with_context/1" do
    test "a step's own config can't claim another organization or pipeline", %{
      org_id: org_id,
      other_org_id: other_org_id
    } do
      pipeline =
        pipeline_fixture(org_id, %{
          steps: %{
            "version" => "1.0",
            "steps" => [
              %{
                "type" => "native",
                "operation" => "map",
                "config" => %{"organization_id" => other_org_id, "pipeline_id" => -1}
              }
            ]
          }
        })

      %{"steps" => [%{"config" => config}]} = Flux.Pipeline.Runner.steps_with_context(pipeline)

      assert config["organization_id"] == org_id
      assert config["pipeline_id"] == pipeline.id
    end
  end

  describe "rollback_pipeline/3" do
    test "drops a sink the organization doesn't own and still rolls back", %{
      org_id: org_id,
      own_sink: own,
      foreign_sink: foreign
    } do
      pipeline = pipeline_fixture(org_id, %{sink_ids: [own.id]})

      # A version row written before sinks were checked, or tampered with.
      Repo.insert!(%PipelineVersion{
        pipeline_id: pipeline.id,
        version: 99,
        name: pipeline.name,
        source_queue: pipeline.source_queue,
        config: %{},
        steps: %{"version" => "1.0", "steps" => []},
        sink_ids: [own.id, foreign.id]
      })

      assert {:ok, rolled_back} = Pipelines.rollback_pipeline(pipeline, 99)
      assert rolled_back.sink_ids == [own.id]
    end

    test "still rolls back to a version whose sink was deleted since", %{
      org_id: org_id,
      own_sink: own
    } do
      gone = sink_fixture(org_id)
      pipeline = pipeline_fixture(org_id, %{sink_ids: [gone.id]})
      {:ok, pipeline} = Pipelines.update_pipeline(pipeline, %{sink_ids: [own.id]})
      {:ok, _} = Sinks.delete_sink(gone)

      assert {:ok, rolled_back} = Pipelines.rollback_pipeline(pipeline, 1)
      assert rolled_back.sink_ids == []
    end
  end

  describe "Sinks.get_sinks_by_ids/2" do
    test "returns only the organization's own enabled sinks", %{
      org_id: org_id,
      own_sink: own,
      foreign_sink: foreign
    } do
      assert [%{id: id}] = Sinks.get_sinks_by_ids([own.id, foreign.id], org_id)
      assert id == own.id
    end
  end

  defp attrs(org_id, overrides) do
    Enum.into(overrides, %{
      name: "p-#{System.unique_integer([:positive])}",
      source_queue: "q",
      steps: %{"version" => "1.0", "steps" => []},
      organization_id: org_id
    })
  end

  defp org do
    Repo.insert!(%Organization{
      name: "Org #{System.unique_integer([:positive])}",
      slug: "org-#{System.unique_integer([:positive])}"
    })
  end
end
