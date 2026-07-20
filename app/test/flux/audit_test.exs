defmodule Flux.AuditTest do
  # async: false — set_active/1 and the ambient context mutate global/process state.
  use ExUnit.Case, async: false

  alias Flux.Audit
  alias Flux.Audit.{Context, Event}

  setup do
    # The audit provider registry is global (a single ETS entry), so a test that
    # swaps in a capturing/raising provider must restore the prior one on exit —
    # otherwise the leaked provider survives this async: false module and, under
    # some seeds, fires {:audit_event, _} into a later LiveView's process (e.g.
    # SystemSettingsLive), crashing it in handle_info. Capture-and-restore keeps
    # the mutation contained to this module.
    previous = Audit.Registry.active()
    Audit.Registry.set_active(Flux.Audit.Providers.Community)

    on_exit(fn ->
      Context.clear()
      Audit.Registry.set_active(previous)
    end)

    :ok
  end

  describe "Community provider (default)" do
    test "logs are no-ops and reads are empty" do
      assert Audit.log(%{organization_id: 1, action: :login}) == :ok
      assert Audit.list_logs(1) == []
      assert Audit.count(1) == 0
    end

    test "export refuses with :pro_required" do
      assert Audit.export_logs(1, :csv) == {:error, {:pro_required, :audit_log}}
      assert Audit.export_logs(1, :json) == {:error, {:pro_required, :audit_log}}
    end

    test "prune is a no-op" do
      assert Audit.prune() == :ok
    end
  end

  describe "log/1 robustness" do
    test "never raises even when the provider blows up" do
      Audit.Registry.set_active(__MODULE__.RaisingProvider)
      assert Audit.log(%{organization_id: 1, action: :login}) == :ok
    end
  end

  describe "Event.normalize/1" do
    test "resolves a Scope actor into actor_id/actor_type and derives org" do
      scope = %Flux.Accounts.Scope{
        user: %Flux.Accounts.User{id: 7},
        organization_id: 42,
        organization_role: "owner"
      }

      event = Event.normalize(%{actor: scope, action: :pipeline_created})

      assert event.actor_id == 7
      assert event.actor_type == "user"
      assert event.organization_id == 42
      assert event.action == "pipeline_created"
    end

    test "defaults to a system actor when none is given" do
      event = Event.normalize(%{action: :magic_link_sent})
      assert event.actor_id == nil
      assert event.actor_type == "system"
    end

    test "resolves an api_key actor and folds its prefix into metadata" do
      event =
        Event.normalize(%{
          actor: {:api_key, %{id: 9, prefix: "flux_pk_abcd"}},
          action: :api_key_created
        })

      assert event.actor_id == 9
      assert event.actor_type == "api_key"
      assert event.metadata["api_key_prefix"] == "flux_pk_abcd"
    end

    test "stringifies changes and metadata keys" do
      event =
        Event.normalize(%{action: :sink_updated, changes: %{name: "x"}, metadata: %{ip: "1"}})

      assert event.changes == %{"name" => "x"}
      assert event.metadata == %{"ip" => "1"}
    end
  end

  describe "ambient context" do
    test "log/1 merges actor and metadata from the process context" do
      Audit.Registry.set_active(__MODULE__.CapturingProvider)
      scope = %Flux.Accounts.Scope{user: %Flux.Accounts.User{id: 3}, organization_id: 5}
      Context.put(%{actor: scope, organization_id: 5, metadata: %{"ip_address" => "10.0.0.1"}})

      Audit.log(%{action: :pipeline_deleted, resource_type: :pipeline, resource_id: 99})

      assert_received {:audit_event, event}
      assert event.actor_id == 3
      assert event.organization_id == 5
      assert event.metadata["ip_address"] == "10.0.0.1"
      assert event.action == "pipeline_deleted"
    end

    test "explicit metadata merges over context metadata" do
      Audit.Registry.set_active(__MODULE__.CapturingProvider)
      Context.put(%{metadata: %{"ip_address" => "10.0.0.1"}})

      Audit.log(%{action: :login, metadata: %{"user_agent" => "curl"}})

      assert_received {:audit_event, event}
      assert event.metadata["ip_address"] == "10.0.0.1"
      assert event.metadata["user_agent"] == "curl"
    end
  end

  describe "diff/1" do
    test "produces field => from/to from a changeset" do
      changeset =
        Ecto.Changeset.change(%Flux.Sinks.Sink{name: "old", enabled: false}, %{
          name: "new",
          enabled: true
        })

      diff = Audit.diff(changeset)
      assert diff["name"] == %{"from" => "old", "to" => "new"}
      assert diff["enabled"] == %{"from" => false, "to" => true}
    end

    test "redacts requested fields" do
      changeset =
        Ecto.Changeset.change(%Flux.Sinks.Sink{config: %{"a" => 1}}, %{config: %{"secret" => 2}})

      diff = Audit.diff(changeset, redact: [:config])
      assert diff["config"] == %{"from" => "«redacted»", "to" => "«redacted»"}
    end
  end

  defmodule RaisingProvider do
    @behaviour Flux.Audit.Provider
    def log(_event), do: raise("boom")
    def list(_o, _f, _opts), do: []
    def count(_o, _f), do: 0
    def export(_o, _f), do: {:error, :nope}
    def prune(_opts), do: :ok
  end

  defmodule CapturingProvider do
    @behaviour Flux.Audit.Provider
    def log(event) do
      send(self(), {:audit_event, event})
      :ok
    end

    def list(_o, _f, _opts), do: []
    def count(_o, _f), do: 0
    def export(_o, _f), do: []
    def prune(_opts), do: :ok
  end
end
