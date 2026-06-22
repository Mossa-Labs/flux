defmodule Flux.Pipelines.PortableConfigTest do
  use Flux.DataCase, async: true

  import Flux.AccountsFixtures
  import Flux.StructureFixtures
  import Flux.SinksFixtures
  import Flux.PipelinesFixtures

  alias Flux.Pipelines.PortableConfig

  setup do
    org = organization_fixture(user_scope_fixture())
    %{org: org}
  end

  describe "export_pipeline/1" do
    test "builds the envelope with sink names in order, no ids/status/org/secrets", %{org: org} do
      a = sink_fixture(org.id, %{name: "alpha"})
      b = sink_fixture(org.id, %{name: "beta"})

      pipeline =
        pipeline_fixture(org.id, %{
          name: "webhook-processor",
          description: "does things",
          source_queue: "webhooks.github",
          destination_queue: "processed.github",
          sink_ids: [b.id, a.id],
          steps: %{"version" => "1.0", "steps" => [%{"type" => "native", "operation" => "map"}]}
        })

      envelope = PortableConfig.export_pipeline(pipeline)

      assert envelope["flux_export"] == "1.0"
      assert is_binary(envelope["exported_at"])

      p = envelope["pipeline"]
      assert p["name"] == "webhook-processor"
      assert p["source_queue"] == "webhooks.github"
      assert p["destination_queue"] == "processed.github"
      # order preserved (sink_ids were [b, a])
      assert p["sink_names"] == ["beta", "alpha"]

      # no ids/status/org leak
      refute Map.has_key?(p, "sink_ids")
      refute Map.has_key?(p, "status")
      refute Map.has_key?(p, "organization_id")
      refute Map.has_key?(p, "id")

      # no sink secrets (the sink config url) anywhere in the serialized envelope
      refute Jason.encode!(envelope) =~ "example.com"
    end

    test "accepts a pipeline id", %{org: org} do
      pipeline = pipeline_fixture(org.id, %{name: "by-id"})
      assert PortableConfig.export_pipeline(pipeline.id)["pipeline"]["name"] == "by-id"
    end
  end

  describe "import_pipeline/3" do
    test "round-trips an exported pipeline into another org", %{org: org} do
      slack = sink_fixture(org.id, %{name: "slack"})
      source = pipeline_fixture(org.id, %{name: "src", sink_ids: [slack.id]})
      envelope = PortableConfig.export_pipeline(source)

      # target org with a sink of the same name
      target = organization_fixture(user_scope_fixture())
      target_sink = sink_fixture(target.id, %{name: "slack"})

      assert {:ok, imported} = PortableConfig.import_pipeline(envelope, target.id)
      assert imported.name == "src"
      assert imported.organization_id == target.id
      assert imported.status == "stopped"
      assert imported.sink_ids == [target_sink.id]
    end

    test "rejects an unsupported envelope version", %{org: org} do
      envelope = %{"flux_export" => "9.9", "pipeline" => %{"name" => "x", "source_queue" => "q"}}

      assert {:error, {:unsupported_version, "9.9"}} =
               PortableConfig.import_pipeline(envelope, org.id)
    end

    test "rejects a malformed envelope", %{org: org} do
      assert {:error, {:invalid_format, _}} =
               PortableConfig.import_pipeline(%{"nope" => 1}, org.id)

      assert {:error, {:invalid_format, _}} =
               PortableConfig.import_pipeline(
                 %{"flux_export" => "1.0", "pipeline" => %{"source_queue" => "q"}},
                 org.id
               )
    end

    test "rejects unknown step operations", %{org: org} do
      envelope = %{
        "flux_export" => "1.0",
        "pipeline" => %{
          "name" => "bad-steps",
          "source_queue" => "q",
          "steps" => %{
            "version" => "1.0",
            "steps" => [%{"type" => "native", "operation" => "teleport"}]
          }
        }
      }

      assert {:error, {:invalid_steps, message}} =
               PortableConfig.import_pipeline(envelope, org.id)

      assert message =~ "teleport"
    end

    test "reports missing sinks", %{org: org} do
      envelope = %{
        "flux_export" => "1.0",
        "pipeline" => %{
          "name" => "needs-sinks",
          "source_queue" => "q",
          "sink_names" => ["ghost", "phantom"]
        }
      }

      assert {:error, {:missing_sinks, missing}} =
               PortableConfig.import_pipeline(envelope, org.id)

      assert Enum.sort(missing) == ["ghost", "phantom"]
    end

    test "name collision returns a changeset error", %{org: org} do
      pipeline_fixture(org.id, %{name: "taken"})

      envelope = %{
        "flux_export" => "1.0",
        "pipeline" => %{"name" => "taken", "source_queue" => "q"}
      }

      assert {:error, %Ecto.Changeset{} = changeset} =
               PortableConfig.import_pipeline(envelope, org.id)

      # Unique (organization_id, name) violation attaches to :organization_id.
      assert Enum.any?(changeset.errors, fn {_f, {_m, opts}} -> opts[:constraint] == :unique end)
    end

    test "name override imports a renamed copy", %{org: org} do
      pipeline_fixture(org.id, %{name: "taken"})

      envelope = %{
        "flux_export" => "1.0",
        "pipeline" => %{"name" => "taken", "source_queue" => "q"}
      }

      assert {:ok, imported} =
               PortableConfig.import_pipeline(envelope, org.id, name: "taken (copy)")

      assert imported.name == "taken (copy)"
    end

    test "rejects an envelope with no pipeline object", %{org: org} do
      assert {:error, {:invalid_format, _}} =
               PortableConfig.import_pipeline(%{"flux_export" => "1.0"}, org.id)
    end

    test "rejects non-list sink_names", %{org: org} do
      envelope = %{
        "flux_export" => "1.0",
        "pipeline" => %{"name" => "p", "source_queue" => "q", "sink_names" => "not-a-list"}
      }

      assert {:error, {:invalid_format, message}} =
               PortableConfig.import_pipeline(envelope, org.id)

      assert message =~ "sink_names"
    end

    test "skips script steps during IR validation", %{org: org} do
      envelope = %{
        "flux_export" => "1.0",
        "pipeline" => %{
          "name" => "scripted",
          "source_queue" => "q",
          "steps" => %{
            "version" => "1.0",
            "steps" => [%{"type" => "script", "language" => "lua", "code" => "return data"}]
          }
        }
      }

      assert {:ok, imported} = PortableConfig.import_pipeline(envelope, org.id)
      assert imported.name == "scripted"
    end
  end

  describe "suggested_filename/1" do
    test "slugifies a pipeline name" do
      assert PortableConfig.suggested_filename("Webhook Processor!") ==
               "webhook-processor.flux.json"
    end

    test "falls back to 'pipeline' for a name with no slug characters" do
      assert PortableConfig.suggested_filename("!!!") == "pipeline.flux.json"
    end

    test "accepts a pipeline struct", %{org: org} do
      pipeline = pipeline_fixture(org.id, %{name: "from-struct"})
      assert PortableConfig.suggested_filename(pipeline) == "from-struct.flux.json"
    end
  end
end
