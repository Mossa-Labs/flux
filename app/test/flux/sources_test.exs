defmodule Flux.SourcesTest do
  use Flux.DataCase

  alias Flux.Sources
  alias Flux.Sources.Source

  import Flux.AccountsFixtures
  import Flux.StructureFixtures

  setup do
    scope = user_scope_fixture()
    %{org_id: scope.organization_id, scope: scope}
  end

  defp webhook_attrs(org_id, attrs \\ %{}) do
    Map.merge(
      %{
        "name" => "github-hook",
        "type" => "webhook",
        "config" => %{"source" => "github"},
        "organization_id" => org_id
      },
      attrs
    )
  end

  describe "create_source/1" do
    test "creates a valid webhook source", %{org_id: org_id} do
      assert {:ok, %Source{} = source} = Sources.create_source(webhook_attrs(org_id))
      assert source.type == "webhook"
      assert source.enabled
    end

    test "creates a valid poll source", %{org_id: org_id} do
      attrs = %{
        "name" => "orders-poll",
        "type" => "poll",
        "config" => %{"source_id" => "orders", "url" => "https://api.example.com/orders"},
        "organization_id" => org_id
      }

      assert {:ok, %Source{type: "poll"}} = Sources.create_source(attrs)
    end

    test "rejects an unknown type", %{org_id: org_id} do
      attrs = webhook_attrs(org_id, %{"type" => "carrier-pigeon"})
      assert {:error, changeset} = Sources.create_source(attrs)
      assert "is invalid" in errors_on(changeset).type
    end

    test "gates the Pro kafka source with a pro_required config error", %{org_id: org_id} do
      attrs = %{
        "name" => "events-kafka",
        "type" => "kafka",
        "config" => %{"topic" => "events", "bootstrap_servers" => "broker:9092"},
        "organization_id" => org_id
      }

      assert {:error, changeset} = Sources.create_source(attrs)
      assert Enum.any?(errors_on(changeset).config, &(&1 =~ "Flux Pro"))
    end

    test "enforces unique name per organization", %{org_id: org_id} do
      assert {:ok, _} = Sources.create_source(webhook_attrs(org_id))
      assert {:error, changeset} = Sources.create_source(webhook_attrs(org_id))
      # The composite unique index reports under the first field, like sinks.
      assert "has already been taken" in errors_on(changeset).organization_id
    end
  end

  describe "queue_name/1 — links a source to the pipelines it feeds" do
    test "webhook source resolves its internal queue", %{org_id: org_id} do
      {:ok, source} = Sources.create_source(webhook_attrs(org_id))
      assert "webhooks.github" = Sources.queue_name(source)
    end
  end

  describe "list/enabled" do
    test "list_enabled_sources/1 excludes disabled", %{org_id: org_id} do
      {:ok, enabled} = Sources.create_source(webhook_attrs(org_id))

      {:ok, _disabled} =
        Sources.create_source(webhook_attrs(org_id, %{"name" => "off", "enabled" => false}))

      enabled_sources = Sources.list_enabled_sources(org_id)
      assert enabled in enabled_sources
      assert Enum.all?(enabled_sources, & &1.enabled)
    end

    test "list_sources/1 is org-scoped", %{org_id: org_id, scope: scope} do
      {:ok, _} = Sources.create_source(webhook_attrs(org_id))
      other_org = organization_fixture(scope)

      assert Enum.all?(Sources.list_sources(org_id), &(&1.organization_id == org_id))
      assert Sources.list_sources(other_org.id) == []
    end
  end
end
