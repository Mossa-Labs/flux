defmodule Flux.Pipeline.SupervisionLocalTest do
  @moduledoc """
  The Community edition is single-node: pipeline supervision uses
  `Flux.Pipeline.Supervision.Local` (plain Registry + DynamicSupervisor).
  Verifies the single-node invariants — a pipeline runs at most once on this
  node and starting it again is idempotent — through the public `Manager` API,
  with no clustering dependency.
  """
  use Flux.DataCase

  import Flux.AccountsFixtures
  import Flux.PipelinesFixtures

  alias Flux.Pipeline.Manager
  alias Flux.Pipeline.Supervision

  setup do
    scope = user_scope_fixture()
    %{org_id: scope.organization_id}
  end

  test "the active supervision backend is the single-node Local impl" do
    assert Supervision.impl() == Flux.Pipeline.Supervision.Local
    assert Supervision.member_count() == 1
    assert Supervision.ready?() == true
  end

  test "a pipeline runs exactly once and re-starting is idempotent", %{org_id: org_id} do
    pipeline = pipeline_fixture(org_id, %{steps: %{"version" => "1.0", "steps" => []}})
    on_exit(fn -> Manager.stop_pipeline(pipeline.id) end)

    assert {:ok, _pid} = Manager.start_pipeline(pipeline.id)
    assert Manager.get_status(pipeline.id) == :running
    assert pipeline.id in Manager.list_running()

    # exactly one runner registered locally
    assert is_pid(Supervision.whereis(pipeline.id))

    # a second start does not spawn a duplicate
    assert {:error, :already_running} = Manager.start_pipeline(pipeline.id)
    assert [pipeline.id] == Enum.filter(Manager.list_running(), &(&1 == pipeline.id))

    assert :ok = Manager.stop_pipeline(pipeline.id)
    assert Manager.get_status(pipeline.id) == :stopped
    assert Supervision.whereis(pipeline.id) == nil
  end

  test "stopping a pipeline that is not running returns an error", %{org_id: org_id} do
    pipeline = pipeline_fixture(org_id, %{steps: %{"version" => "1.0", "steps" => []}})
    assert {:error, :not_running} = Manager.stop_pipeline(pipeline.id)
  end
end
