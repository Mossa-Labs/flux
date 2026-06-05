defmodule Flux.Pipeline.ManagerHordeTest do
  @moduledoc """
  MOS-530: pipelines are cluster-wide singletons via Horde.Registry +
  Horde.DynamicSupervisor. Verifies the single-node invariants the distribution
  relies on — a pipeline runs exactly once and starting it again is idempotent.
  """
  use Flux.DataCase

  import Flux.AccountsFixtures
  import Flux.PipelinesFixtures

  alias Flux.Pipeline.Manager

  setup do
    scope = user_scope_fixture()
    %{org_id: scope.organization_id}
  end

  test "a pipeline runs exactly once and re-starting is idempotent", %{org_id: org_id} do
    pipeline = pipeline_fixture(org_id, %{steps: %{"version" => "1.0", "steps" => []}})
    on_exit(fn -> Manager.stop_pipeline(pipeline.id) end)

    assert {:ok, _pid} = Manager.start_pipeline(pipeline.id)
    assert Manager.get_status(pipeline.id) == :running
    assert pipeline.id in Manager.list_running()

    # exactly one runner registered in the (cluster-wide) Horde.Registry
    assert [{_pid, _}] = Horde.Registry.lookup(Flux.Pipeline.Registry, {:runner, pipeline.id})

    # a second start does not spawn a duplicate
    assert {:error, :already_running} = Manager.start_pipeline(pipeline.id)
    assert [{_pid, _}] = Horde.Registry.lookup(Flux.Pipeline.Registry, {:runner, pipeline.id})

    assert :ok = Manager.stop_pipeline(pipeline.id)
    assert Manager.get_status(pipeline.id) == :stopped
    assert [] = Horde.Registry.lookup(Flux.Pipeline.Registry, {:runner, pipeline.id})
  end
end
