defmodule Flux.Pipelines.PipelineQueueNameTest do
  use Flux.DataCase, async: true

  import Flux.PipelinesFixtures

  alias Flux.Pipelines
  alias Flux.Pipelines.PipelineVersion
  alias Flux.Pipelines.PortableConfig
  alias Flux.Structure.Organization

  # A pipeline names its queues with logical names, which the server places
  # inside the pipeline's own organization. A name that tries to reach outside
  # it (a reserved prefix, another organization's queue) or can't be a broker
  # queue name is refused on every write path.

  @invalid [
    "org.1.webhooks.stripe",
    "ORG.1.webhooks.stripe",
    "amq.gen-x",
    "flux.events.dlq",
    "has space",
    "wild.*",
    "wild.#",
    ".leading-dot",
    String.duplicate("a", 201)
  ]

  setup do
    %{org_id: org().id}
  end

  describe "create_pipeline/2" do
    test "refuses an invalid source_queue", %{org_id: org_id} do
      for name <- @invalid do
        assert {:error, changeset} = Pipelines.create_pipeline(attrs(org_id, source_queue: name)),
               "expected #{inspect(name)} to be refused"

        assert %{source_queue: [_]} = errors_on(changeset)
      end
    end

    test "refuses an invalid destination_queue", %{org_id: org_id} do
      for name <- @invalid do
        assert {:error, changeset} =
                 Pipelines.create_pipeline(attrs(org_id, destination_queue: name)),
               "expected #{inspect(name)} to be refused"

        assert %{destination_queue: [_]} = errors_on(changeset)
      end
    end

    test "refuses an invalid queue in a queue-type source node", %{org_id: org_id} do
      steps = steps_with_source(%{"type" => "queue", "queue" => "flux.events"})

      assert {:error, changeset} = Pipelines.create_pipeline(attrs(org_id, steps: steps))
      assert %{steps: [_]} = errors_on(changeset)
    end

    test "accepts ordinary logical names", %{org_id: org_id} do
      for name <- ["webhooks.stripe", "polling.feed", "default", "events.incoming", "a-b_c.9"] do
        assert {:ok, _} =
                 Pipelines.create_pipeline(
                   attrs(org_id, source_queue: name, destination_queue: name <> ".out")
                 )
      end
    end

    test "accepts a blank destination_queue", %{org_id: org_id} do
      assert {:ok, _} = Pipelines.create_pipeline(attrs(org_id, destination_queue: nil))
      assert {:ok, _} = Pipelines.create_pipeline(attrs(org_id, destination_queue: ""))
    end

    test "doesn't treat an external broker's queue name as an internal one", %{org_id: org_id} do
      # rabbitmq_external's "queue" names the customer's own broker queue.
      steps =
        steps_with_source(%{
          "type" => "rabbitmq_external",
          "host" => "broker.example.com",
          "queue" => "Orders Queue"
        })

      assert {:ok, _} = Pipelines.create_pipeline(attrs(org_id, steps: steps))
    end
  end

  describe "update_pipeline/3" do
    test "refuses an invalid source_queue", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id, %{source_queue: "webhooks.stripe"})
      other = org()

      assert {:error, changeset} =
               Pipelines.update_pipeline(pipeline, %{
                 source_queue: "org.#{other.id}.webhooks.stripe"
               })

      assert %{source_queue: [_]} = errors_on(changeset)
      assert Repo.reload(pipeline).source_queue == "webhooks.stripe"
    end

    test "refuses an invalid destination_queue", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id)

      assert {:error, changeset} =
               Pipelines.update_pipeline(pipeline, %{destination_queue: "org.1.x"})

      assert %{destination_queue: [_]} = errors_on(changeset)
    end
  end

  describe "rollback_pipeline/3" do
    test "refuses a version whose queue reaches outside the organization", %{org_id: org_id} do
      pipeline = pipeline_fixture(org_id, %{source_queue: "webhooks.stripe"})

      # A version row written before queue names were checked, or tampered with.
      Repo.insert!(%PipelineVersion{
        pipeline_id: pipeline.id,
        version: 99,
        name: pipeline.name,
        source_queue: "org.1.webhooks.stripe",
        config: %{},
        steps: %{"version" => "1.0", "steps" => []},
        sink_ids: []
      })

      assert {:error, %Ecto.Changeset{} = changeset} = Pipelines.rollback_pipeline(pipeline, 99)
      assert %{source_queue: [_]} = errors_on(changeset)
      assert Repo.reload(pipeline).source_queue == "webhooks.stripe"
    end
  end

  describe "PortableConfig.import_pipeline/3" do
    test "refuses an envelope whose queue reaches outside the organization", %{org_id: org_id} do
      envelope =
        org_id
        |> pipeline_fixture()
        |> PortableConfig.export_pipeline()
        |> put_in(["pipeline", "name"], "imported")
        |> put_in(["pipeline", "source_queue"], "org.1.webhooks.stripe")

      assert {:error, %Ecto.Changeset{} = changeset} =
               PortableConfig.import_pipeline(envelope, org_id)

      assert %{source_queue: [_]} = errors_on(changeset)
    end
  end

  describe "Pipeline.consumed_queue/1" do
    alias Flux.Pipelines.Pipeline

    test "a queue-type source node's queue wins over source_queue" do
      for config <- [%{"type" => "queue", "queue" => "events.in"}, %{"queue" => "events.in"}] do
        pipeline = %Pipeline{source_queue: "fallback", steps: steps_with_source(config)}
        assert Pipeline.consumed_queue(pipeline) == "events.in"
      end
    end

    test "any other source type is fed through source_queue" do
      config = %{"type" => "rabbitmq_external", "queue" => "Orders Queue"}

      pipeline = %Pipeline{
        source_queue: "external.orders",
        steps: steps_with_source(config)
      }

      assert Pipeline.consumed_queue(pipeline) == "external.orders"
    end

    test "falls back to source_queue without a source node queue" do
      for steps <- [
            %{"version" => "1.0", "steps" => []},
            steps_with_source(%{"type" => "webhook", "webhookPath" => "github"}),
            steps_with_source(%{"type" => "queue", "queue" => ""})
          ] do
        assert Pipeline.consumed_queue(%Pipeline{source_queue: "webhooks.x", steps: steps}) ==
                 "webhooks.x"
      end
    end
  end

  describe "Flux.Release.queue_name_findings/1" do
    test "lists pipelines and versions whose queue names can't be placed in the organization",
         %{org_id: org_id} do
      good = pipeline_fixture(org_id, %{source_queue: "webhooks.ok"})

      # Rows written before queue names were checked.
      bad =
        Repo.insert!(%Flux.Pipelines.Pipeline{
          name: "legacy-#{System.unique_integer([:positive])}",
          source_queue: "org.1.webhooks.stripe",
          destination_queue: "has space",
          steps: steps_with_source(%{"type" => "queue", "queue" => "amq.x"}),
          organization_id: org_id
        })

      Repo.insert!(%PipelineVersion{
        pipeline_id: good.id,
        version: 50,
        name: good.name,
        source_queue: "flux.events",
        config: %{},
        steps: %{"version" => "1.0", "steps" => []},
        sink_ids: []
      })

      findings = Flux.Release.queue_name_findings(Repo)

      assert %{table: "pipelines", id: bad.id, field: :source_queue, reason: :reserved_prefix} in Enum.map(
               findings,
               &Map.take(&1, [:table, :id, :field, :reason])
             )

      assert Enum.any?(
               findings,
               &match?(%{id: id, field: :destination_queue} when id == bad.id, &1)
             )

      assert Enum.any?(
               findings,
               &match?(%{id: id, field: :source_node_queue} when id == bad.id, &1)
             )

      assert Enum.any?(
               findings,
               &match?(
                 %{table: "pipeline_versions", pipeline_id: id, organization_id: ^org_id}
                 when id == good.id,
                 &1
               )
             )

      refute Enum.any?(findings, &match?(%{table: "pipelines", id: id} when id == good.id, &1))
    end
  end

  defp steps_with_source(source_config) do
    %{
      "version" => "1.0",
      "steps" => [],
      "nodes" => [%{"id" => "src", "type" => "source", "sourceConfig" => source_config}]
    }
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
