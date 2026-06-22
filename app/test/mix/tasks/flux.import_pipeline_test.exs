defmodule Mix.Tasks.Flux.ImportPipelineTest do
  use Flux.DataCase, async: true

  import ExUnit.CaptureIO
  import Flux.AccountsFixtures
  import Flux.StructureFixtures
  import Flux.PipelinesFixtures

  alias Flux.Pipelines
  alias Mix.Tasks.Flux.ImportPipeline

  setup do
    %{org: organization_fixture(user_scope_fixture())}
  end

  test "imports a stopped pipeline with --org", %{org: org} do
    path = write_envelope("cli-import")

    out = capture_io(fn -> ImportPipeline.run([path, "--org", to_string(org.id)]) end)
    assert out =~ "Imported pipeline"

    assert [pipeline] = Pipelines.list_pipelines(org.id)
    assert pipeline.name == "cli-import"
    assert pipeline.status == "stopped"
  end

  test "applies a --name override", %{org: org} do
    pipeline_fixture(org.id, %{name: "dup"})
    path = write_envelope("dup")

    capture_io(fn ->
      ImportPipeline.run([path, "--org", to_string(org.id), "--name", "dup (copy)"])
    end)

    assert Enum.any?(Pipelines.list_pipelines(org.id), &(&1.name == "dup (copy)"))
  end

  test "raises when --org omitted and multiple organizations exist", %{org: org} do
    organization_fixture(user_scope_fixture())
    path = write_envelope("ambiguous")

    assert_raise Mix.Error, ~r/Multiple organizations/, fn ->
      capture_io(fn -> ImportPipeline.run([path]) end)
    end

    # nothing imported into the original org
    refute Enum.any?(Pipelines.list_pipelines(org.id), &(&1.name == "ambiguous"))
  end

  test "raises on invalid JSON", %{org: org} do
    path = Path.join(System.tmp_dir!(), "bad-#{System.unique_integer([:positive])}.json")
    File.write!(path, "{ not json")
    on_exit(fn -> File.rm(path) end)

    assert_raise Mix.Error, ~r/Invalid JSON/, fn ->
      ImportPipeline.run([path, "--org", to_string(org.id)])
    end
  end

  test "raises on a name collision", %{org: org} do
    pipeline_fixture(org.id, %{name: "taken"})
    path = write_envelope("taken")

    assert_raise Mix.Error, ~r/already exists/, fn ->
      capture_io(fn -> ImportPipeline.run([path, "--org", to_string(org.id)]) end)
    end
  end

  test "raises for an unsupported version", %{org: org} do
    path =
      write_json(%{"flux_export" => "9.9", "pipeline" => %{"name" => "x", "source_queue" => "q"}})

    assert_raise Mix.Error, ~r/Unsupported export version/, fn ->
      ImportPipeline.run([path, "--org", to_string(org.id)])
    end
  end

  test "raises with the missing sink names", %{org: org} do
    path =
      write_json(%{
        "flux_export" => "1.0",
        "pipeline" => %{"name" => "x", "source_queue" => "q", "sink_names" => ["ghost"]}
      })

    assert_raise Mix.Error, ~r/ghost/, fn ->
      ImportPipeline.run([path, "--org", to_string(org.id)])
    end
  end

  test "raises for unknown step operations", %{org: org} do
    path =
      write_json(%{
        "flux_export" => "1.0",
        "pipeline" => %{
          "name" => "x",
          "source_queue" => "q",
          "steps" => %{
            "version" => "1.0",
            "steps" => [%{"type" => "native", "operation" => "teleport"}]
          }
        }
      })

    assert_raise Mix.Error, ~r/teleport/, fn ->
      ImportPipeline.run([path, "--org", to_string(org.id)])
    end
  end

  test "raises with details for an invalid changeset", %{org: org} do
    # A non-map steps value fails the schema's :map cast — a non-unique
    # changeset error that exercises the detailed-error path.
    path =
      write_json(%{
        "flux_export" => "1.0",
        "pipeline" => %{"name" => "x", "source_queue" => "q", "steps" => [1, 2, 3]}
      })

    assert_raise Mix.Error, ~r/Import failed/, fn ->
      ImportPipeline.run([path, "--org", to_string(org.id)])
    end
  end

  defp write_envelope(name) do
    envelope = %{
      "flux_export" => "1.0",
      "exported_at" => "2026-01-01T00:00:00Z",
      "pipeline" => %{
        "name" => name,
        "source_queue" => "q",
        "steps" => %{"version" => "1.0", "steps" => []}
      }
    }

    write_json(envelope)
  end

  defp write_json(map) do
    path = Path.join(System.tmp_dir!(), "imp-#{System.unique_integer([:positive])}.json")
    File.write!(path, Jason.encode!(map))
    on_exit(fn -> File.rm(path) end)
    path
  end
end
