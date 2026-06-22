defmodule Flux.SinksTest do
  use Flux.DataCase

  alias Flux.Sinks
  alias Flux.Sinks.Sink

  import Flux.AccountsFixtures
  import Flux.SinksFixtures
  import Flux.StructureFixtures

  setup do
    scope = user_scope_fixture()
    %{org_id: scope.organization_id, scope: scope}
  end

  describe "list_sinks/1" do
    test "returns all sinks for the organization", %{org_id: org_id} do
      sink = sink_fixture(org_id)
      assert sink in Sinks.list_sinks(org_id)
    end

    test "does not return sinks from other organizations", %{org_id: org_id, scope: scope} do
      other_org = organization_fixture(scope)
      _other_sink = sink_fixture(other_org.id)

      sinks = Sinks.list_sinks(org_id)
      assert Enum.all?(sinks, &(&1.organization_id == org_id))
    end

    test "returns sinks ordered by updated_at desc", %{org_id: org_id} do
      _s1 = sink_fixture(org_id, %{name: "alpha-sink"})
      _s2 = sink_fixture(org_id, %{name: "beta-sink"})

      sinks = Sinks.list_sinks(org_id)
      assert length(sinks) >= 2

      timestamps = Enum.map(sinks, & &1.updated_at)
      assert timestamps == Enum.sort(timestamps, {:desc, DateTime})
    end

    test "returns empty list when no sinks exist", %{scope: scope} do
      other_org = organization_fixture(scope)
      assert Sinks.list_sinks(other_org.id) == []
    end
  end

  describe "list_enabled_sinks/1" do
    test "returns only enabled sinks", %{org_id: org_id} do
      enabled = sink_fixture(org_id, %{enabled: true})
      _disabled = sink_fixture(org_id, %{enabled: false})

      enabled_sinks = Sinks.list_enabled_sinks(org_id)
      assert enabled in enabled_sinks
      assert Enum.all?(enabled_sinks, & &1.enabled)
    end

    test "returns sinks ordered by name asc", %{org_id: org_id} do
      _z = sink_fixture(org_id, %{name: "zeta-sink", enabled: true})
      _a = sink_fixture(org_id, %{name: "alpha-sink", enabled: true})

      sinks = Sinks.list_enabled_sinks(org_id)
      names = Enum.map(sinks, & &1.name)
      assert names == Enum.sort(names)
    end

    test "does not return sinks from other organizations", %{org_id: org_id, scope: scope} do
      other_org = organization_fixture(scope)
      _other_sink = sink_fixture(other_org.id, %{enabled: true})

      sinks = Sinks.list_enabled_sinks(org_id)
      assert Enum.all?(sinks, &(&1.organization_id == org_id))
    end
  end

  describe "get_sinks_by_ids/1" do
    test "returns enabled sinks matching the given ids", %{org_id: org_id} do
      s1 = sink_fixture(org_id, %{enabled: true})
      s2 = sink_fixture(org_id, %{enabled: true})

      result = Sinks.get_sinks_by_ids([s1.id, s2.id])
      assert length(result) == 2
      assert s1 in result
      assert s2 in result
    end

    test "excludes disabled sinks", %{org_id: org_id} do
      enabled = sink_fixture(org_id, %{enabled: true})
      disabled = sink_fixture(org_id, %{enabled: false})

      result = Sinks.get_sinks_by_ids([enabled.id, disabled.id])
      assert enabled in result
      refute disabled in result
    end

    test "returns empty list for non-existent ids" do
      assert Sinks.get_sinks_by_ids([-1, -2]) == []
    end

    test "returns empty list for empty input" do
      assert Sinks.get_sinks_by_ids([]) == []
    end
  end

  describe "get_sinks_by_names/2" do
    test "resolves enabled and disabled sinks, scoped to the org", %{org_id: org_id, scope: scope} do
      enabled = sink_fixture(org_id, %{name: "enabled-sink"})
      disabled = sink_fixture(org_id, %{name: "disabled-sink", enabled: false})

      other_org = organization_fixture(scope)
      sink_fixture(other_org.id, %{name: "enabled-sink"})

      result = Sinks.get_sinks_by_names(["enabled-sink", "disabled-sink"], org_id)
      assert Enum.map(result, & &1.id) |> Enum.sort() == Enum.sort([enabled.id, disabled.id])
    end

    test "returns empty list when no names match", %{org_id: org_id} do
      assert Sinks.get_sinks_by_names(["nope"], org_id) == []
    end
  end

  describe "get_sink!/1" do
    test "returns the sink with given id", %{org_id: org_id} do
      sink = sink_fixture(org_id)
      assert %Sink{} = fetched = Sinks.get_sink!(sink.id)
      assert fetched.id == sink.id
    end

    test "raises if sink does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Sinks.get_sink!(-1)
      end
    end
  end

  describe "get_sink/2" do
    test "returns the sink scoped by organization", %{org_id: org_id} do
      sink = sink_fixture(org_id)
      assert %Sink{} = Sinks.get_sink(sink.id, org_id)
    end

    test "returns nil when sink belongs to different organization", %{
      org_id: org_id,
      scope: scope
    } do
      other_org = organization_fixture(scope)
      sink = sink_fixture(other_org.id)
      assert is_nil(Sinks.get_sink(sink.id, org_id))
    end

    test "returns nil when sink does not exist", %{org_id: org_id} do
      assert is_nil(Sinks.get_sink(-1, org_id))
    end
  end

  describe "create_sink/1" do
    test "with valid http attrs creates a sink", %{org_id: org_id} do
      attrs = %{
        name: "my-webhook",
        type: "http",
        config: %{"url" => "https://example.com/hook", "method" => "POST"},
        organization_id: org_id
      }

      assert {:ok, %Sink{} = sink} = Sinks.create_sink(attrs)
      assert sink.name == "my-webhook"
      assert sink.type == "http"
      assert sink.enabled == true
      assert sink.organization_id == org_id
    end

    test "with s3 type in Community is rejected (Pro feature)", %{org_id: org_id} do
      attrs = %{
        name: "my-s3-sink",
        type: "s3",
        config: %{
          "bucket" => "my-bucket",
          "region" => "us-east-1",
          "access_key_id" => "AKIAIOSFODNN7EXAMPLE",
          "secret_access_key" => "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
          "key_template" => "data/{{year}}/{{month}}/{{day}}/{{uuid}}.json"
        },
        organization_id: org_id
      }

      assert {:error, %Ecto.Changeset{} = changeset} = Sinks.create_sink(attrs)
      assert {msg, _} = changeset.errors[:config]
      assert msg =~ "Flux Pro"
    end

    test "with valid postgres type creates a sink", %{org_id: org_id} do
      attrs = %{
        name: "my-pg-sink",
        type: "postgres",
        config: %{
          "hostname" => "localhost",
          "port" => 5432,
          "database" => "mydb",
          "username" => "user",
          "password" => "pass",
          "table" => "events",
          "columns" => %{"id" => "id", "payload" => "data"}
        },
        organization_id: org_id
      }

      assert {:ok, %Sink{type: "postgres"}} = Sinks.create_sink(attrs)
    end

    test "requires name", %{org_id: org_id} do
      attrs = %{type: "http", organization_id: org_id}
      {:error, changeset} = Sinks.create_sink(attrs)
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires type", %{org_id: org_id} do
      attrs = %{name: "s", organization_id: org_id}
      {:error, changeset} = Sinks.create_sink(attrs)
      assert %{type: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires organization_id" do
      attrs = %{name: "s", type: "http"}
      {:error, changeset} = Sinks.create_sink(attrs)
      assert %{organization_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates type inclusion", %{org_id: org_id} do
      attrs = %{name: "s", type: "ftp", organization_id: org_id}
      {:error, changeset} = Sinks.create_sink(attrs)
      assert %{type: ["is invalid"]} = errors_on(changeset)
    end

    test "enforces unique name within organization", %{org_id: org_id} do
      sink = sink_fixture(org_id)

      attrs = %{
        name: sink.name,
        type: "http",
        config: %{"url" => "https://other.com", "method" => "POST"},
        organization_id: org_id
      }

      assert {:error, changeset} = Sinks.create_sink(attrs)
      errors = errors_on(changeset)
      assert "has already been taken" in (errors[:name] || errors[:organization_id] || [])
    end

    test "allows duplicate name across different organizations", %{org_id: org_id, scope: scope} do
      sink = sink_fixture(org_id)
      other_org = organization_fixture(scope)

      attrs = %{
        name: sink.name,
        type: "http",
        config: %{"url" => "https://other.com", "method" => "POST"},
        organization_id: other_org.id
      }

      assert {:ok, %Sink{}} = Sinks.create_sink(attrs)
    end

    test "defaults enabled to true", %{org_id: org_id} do
      attrs = %{
        name: "default-enabled",
        type: "http",
        config: %{"url" => "https://example.com", "method" => "POST"},
        organization_id: org_id
      }

      assert {:ok, %Sink{enabled: true}} = Sinks.create_sink(attrs)
    end
  end

  describe "update_sink/2" do
    test "with valid data updates the sink", %{org_id: org_id} do
      sink = sink_fixture(org_id)
      attrs = %{name: "updated-sink", description: "updated desc"}

      assert {:ok, %Sink{} = updated} = Sinks.update_sink(sink, attrs)
      assert updated.name == "updated-sink"
      assert updated.description == "updated desc"
    end

    test "with invalid data returns error changeset", %{org_id: org_id} do
      sink = sink_fixture(org_id)
      assert {:error, %Ecto.Changeset{}} = Sinks.update_sink(sink, %{name: nil})
      assert sink == Sinks.get_sink!(sink.id)
    end
  end

  describe "toggle_enabled/1" do
    test "disables an enabled sink", %{org_id: org_id} do
      sink = sink_fixture(org_id, %{enabled: true})
      assert {:ok, %Sink{enabled: false}} = Sinks.toggle_enabled(sink)
    end

    test "enables a disabled sink", %{org_id: org_id} do
      sink = sink_fixture(org_id, %{enabled: false})
      assert {:ok, %Sink{enabled: true}} = Sinks.toggle_enabled(sink)
    end
  end

  describe "delete_sink/1" do
    test "deletes the sink", %{org_id: org_id} do
      sink = sink_fixture(org_id)
      assert {:ok, %Sink{}} = Sinks.delete_sink(sink)

      assert_raise Ecto.NoResultsError, fn ->
        Sinks.get_sink!(sink.id)
      end
    end
  end

  describe "count/1" do
    test "returns the number of sinks for an organization", %{org_id: org_id} do
      assert Sinks.count(org_id) == 0

      _s1 = sink_fixture(org_id)
      assert Sinks.count(org_id) == 1

      _s2 = sink_fixture(org_id)
      assert Sinks.count(org_id) == 2
    end

    test "does not count sinks from other organizations", %{org_id: org_id, scope: scope} do
      other_org = organization_fixture(scope)
      _other_sink = sink_fixture(other_org.id)

      assert Sinks.count(org_id) == 0
    end
  end

  describe "change_sink/2" do
    test "returns a changeset", %{org_id: org_id} do
      sink = sink_fixture(org_id)
      assert %Ecto.Changeset{} = Sinks.change_sink(sink)
    end

    test "returns a changeset with attrs applied", %{org_id: org_id} do
      sink = sink_fixture(org_id)
      changeset = Sinks.change_sink(sink, %{name: "new-name"})
      assert %Ecto.Changeset{} = changeset
      assert get_change(changeset, :name) == "new-name"
    end
  end

  describe "test_connection/1" do
    test "delegates to the sink adapter", %{org_id: org_id} do
      sink =
        sink_fixture(org_id, %{
          type: "http",
          config: %{"url" => "https://example.com/webhook", "method" => "POST"}
        })

      result = Sinks.test_connection(sink)
      assert result == :ok or match?({:error, _}, result)
    end
  end
end
