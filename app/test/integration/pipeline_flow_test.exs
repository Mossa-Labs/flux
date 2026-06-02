defmodule Flux.Integration.PipelineFlowTest do
  @moduledoc """
  Integration tests for the end-to-end pipeline lifecycle:
  create org -> create pipeline -> start -> stop.

  These tests exercise the Manager GenServer against real DB-backed
  pipelines using the infrastructure started by the application
  (Registry, DynamicSupervisor, AI.Detector, Metrics, Manager).
  """

  use Flux.DataCase

  alias Flux.Pipeline.Manager
  alias Flux.Pipelines

  import Flux.AccountsFixtures
  import Flux.PipelinesFixtures

  setup do
    scope = user_scope_fixture()
    org_id = scope.organization_id

    {:ok, scope: scope, org_id: org_id}
  end

  describe "full pipeline lifecycle" do
    test "create, start, and stop a pipeline", %{org_id: org_id} do
      # 1. Create a pipeline with a rename step
      pipeline =
        pipeline_fixture(org_id, %{
          steps: %{
            "version" => "1.0",
            "steps" => [
              %{
                "operation" => "rename",
                "config" => %{"from" => "old_name", "to" => "new_name"}
              }
            ]
          }
        })

      # Verify it was persisted
      assert %Pipelines.Pipeline{} = Pipelines.get_pipeline!(pipeline.id)
      assert pipeline.status == "stopped"

      # 2. Start the pipeline via Manager
      assert {:ok, _pid} = Manager.start_pipeline(pipeline.id)

      # 3. Verify it is running
      assert Manager.get_status(pipeline.id) == :running
      assert pipeline.id in Manager.list_running()

      # 4. Verify the DB status was updated to active
      updated = Pipelines.get_pipeline!(pipeline.id)
      assert updated.status == "active"

      # 5. Stop the pipeline
      assert :ok = Manager.stop_pipeline(pipeline.id)

      # 6. Verify it is stopped
      assert Manager.get_status(pipeline.id) == :stopped
      refute pipeline.id in Manager.list_running()

      # 7. Verify the DB status was updated to stopped
      stopped = Pipelines.get_pipeline!(pipeline.id)
      assert stopped.status == "stopped"
    end
  end

  describe "error handling" do
    test "cannot start non-existent pipeline" do
      assert {:error, :not_found} = Manager.start_pipeline(999_999)
    end

    test "cannot start already running pipeline", %{org_id: org_id} do
      pipeline =
        pipeline_fixture(org_id, %{
          steps: %{"version" => "1.0", "steps" => []}
        })

      assert {:ok, _pid} = Manager.start_pipeline(pipeline.id)
      assert Manager.get_status(pipeline.id) == :running

      # Attempting to start again should fail
      assert {:error, :already_running} = Manager.start_pipeline(pipeline.id)

      # Cleanup: stop the pipeline
      assert :ok = Manager.stop_pipeline(pipeline.id)
    end

    test "cannot stop non-running pipeline", %{org_id: org_id} do
      pipeline =
        pipeline_fixture(org_id, %{
          steps: %{"version" => "1.0", "steps" => []}
        })

      # Pipeline is stopped by default
      assert Manager.get_status(pipeline.id) == :stopped
      assert {:error, :not_running} = Manager.stop_pipeline(pipeline.id)
    end
  end

  describe "pipeline status tracking" do
    test "get_status returns :stopped for unknown pipeline IDs" do
      # A pipeline ID that has never been started returns :stopped
      # because the Registry has no entry for it
      assert Manager.get_status(-1) == :stopped
    end

    test "list_running does not include stopped pipelines", %{org_id: org_id} do
      pipeline =
        pipeline_fixture(org_id, %{
          steps: %{"version" => "1.0", "steps" => []}
        })

      # Before starting, pipeline should not be in running list
      refute pipeline.id in Manager.list_running()

      # Start and verify it appears
      assert {:ok, _pid} = Manager.start_pipeline(pipeline.id)
      assert pipeline.id in Manager.list_running()

      # Stop and verify it disappears
      assert :ok = Manager.stop_pipeline(pipeline.id)
      refute pipeline.id in Manager.list_running()
    end
  end
end
