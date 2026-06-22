defmodule Mix.Tasks.Flux.ExportPipelineTest do
  use Flux.DataCase, async: true

  import ExUnit.CaptureIO
  import Flux.AccountsFixtures
  import Flux.StructureFixtures
  import Flux.PipelinesFixtures

  alias Mix.Tasks.Flux.ExportPipeline

  setup do
    %{org: organization_fixture(user_scope_fixture())}
  end

  test "prints the envelope JSON to stdout", %{org: org} do
    pipeline = pipeline_fixture(org.id, %{name: "exp"})

    out = capture_io(fn -> ExportPipeline.run([to_string(pipeline.id)]) end)

    assert {:ok, decoded} = Jason.decode(out)
    assert decoded["flux_export"] == "1.0"
    assert decoded["pipeline"]["name"] == "exp"
  end

  test "writes to a file with --out", %{org: org} do
    pipeline = pipeline_fixture(org.id, %{name: "exp2"})
    path = Path.join(System.tmp_dir!(), "exp-#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm(path) end)

    capture_io(fn -> ExportPipeline.run([to_string(pipeline.id), "--out", path]) end)

    assert {:ok, decoded} = path |> File.read!() |> Jason.decode()
    assert decoded["pipeline"]["name"] == "exp2"
  end

  test "raises without an id" do
    assert_raise Mix.Error, fn -> ExportPipeline.run([]) end
  end

  test "raises for an unknown pipeline" do
    assert_raise Mix.Error, fn -> ExportPipeline.run(["999999"]) end
  end
end
