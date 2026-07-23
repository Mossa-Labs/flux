defmodule Flux.SecurityTest do
  use Flux.DataCase

  alias Flux.Security
  alias Flux.Security.{Cache, SecuritySettings}

  import Flux.AccountsFixtures

  setup do
    Cache.reset()
    scope = user_scope_fixture()
    %{org_id: scope.organization_id}
  end

  describe "get_settings/1" do
    test "returns an unsaved default with an empty allowlist when none exist", %{org_id: org_id} do
      settings = Security.get_settings(org_id)
      assert %SecuritySettings{ip_allowlist: []} = settings
      refute settings.id
    end

    test "returns the persisted row once created", %{org_id: org_id} do
      {:ok, _} = Security.update_settings(org_id, %{ip_allowlist: ["10.0.0.0/8"]})
      settings = Security.get_settings(org_id)
      assert settings.id
      assert settings.ip_allowlist == ["10.0.0.0/8"]
    end
  end

  describe "update_settings/2" do
    test "creates then updates a single row (upsert)", %{org_id: org_id} do
      {:ok, _} = Security.update_settings(org_id, %{ip_allowlist: ["10.0.0.0/8"]})
      {:ok, _} = Security.update_settings(org_id, %{ip_allowlist: ["192.168.0.0/16"]})

      assert Repo.aggregate(
               from(s in SecuritySettings, where: s.organization_id == ^org_id),
               :count
             ) == 1

      assert Security.get_settings(org_id).ip_allowlist == ["192.168.0.0/16"]
    end

    test "normalizes bare IPs and trims blanks", %{org_id: org_id} do
      {:ok, settings} =
        Security.update_settings(org_id, %{ip_allowlist: ["1.2.3.4", " ", "10.0.0.0/8", ""]})

      assert settings.ip_allowlist == ["1.2.3.4/32", "10.0.0.0/8"]
    end

    test "normalizes a bare IPv6 address to /128", %{org_id: org_id} do
      {:ok, settings} = Security.update_settings(org_id, %{ip_allowlist: ["2001:db8::1"]})
      assert settings.ip_allowlist == ["2001:db8::1/128"]
    end

    test "rejects invalid CIDR ranges", %{org_id: org_id} do
      assert {:error, changeset} =
               Security.update_settings(org_id, %{ip_allowlist: ["not-a-cidr", "10.0.0.0/8"]})

      assert %{ip_allowlist: [msg]} = errors_on(changeset)
      assert msg =~ "invalid CIDR"
    end
  end

  describe "session_timeout_minutes/1" do
    test "defaults to 30 days when unset", %{org_id: org_id} do
      assert Security.session_timeout_minutes(org_id) == 43_200
    end

    test "defaults for a nil org (no organization in scope)" do
      assert Security.session_timeout_minutes(nil) == 43_200
    end

    test "reflects a saved value, cache busted on update", %{org_id: org_id} do
      # Prime the cache with the default.
      assert Security.session_timeout_minutes(org_id) == 43_200

      {:ok, _} = Security.update_settings(org_id, %{session_timeout_minutes: 60})
      assert Security.session_timeout_minutes(org_id) == 60
    end

    test "rejects a timeout below 1 hour", %{org_id: org_id} do
      assert {:error, changeset} =
               Security.update_settings(org_id, %{session_timeout_minutes: 59})

      assert %{session_timeout_minutes: [_]} = errors_on(changeset)
    end

    test "saving the allowlist preserves the timeout and vice versa", %{org_id: org_id} do
      {:ok, _} = Security.update_settings(org_id, %{session_timeout_minutes: 1440})
      {:ok, s} = Security.update_settings(org_id, %{ip_allowlist: ["10.0.0.0/8"]})
      assert s.session_timeout_minutes == 1440
      assert s.ip_allowlist == ["10.0.0.0/8"]
    end
  end

  describe "ip_allowed?/2" do
    test "allows any IP when the allowlist is empty", %{org_id: org_id} do
      assert Security.ip_allowed?(org_id, {203, 0, 113, 5})
    end

    test "allows IPs inside a configured IPv4 range and denies others", %{org_id: org_id} do
      {:ok, _} = Security.update_settings(org_id, %{ip_allowlist: ["10.0.0.0/8"]})

      assert Security.ip_allowed?(org_id, {10, 1, 2, 3})
      refute Security.ip_allowed?(org_id, {192, 168, 1, 1})
    end

    test "matches IPv6 ranges", %{org_id: org_id} do
      {:ok, _} = Security.update_settings(org_id, %{ip_allowlist: ["2001:db8::/32"]})

      {:ok, inside} = :inet.parse_address(~c"2001:db8::1")
      {:ok, outside} = :inet.parse_address(~c"2001:dead::1")

      assert Security.ip_allowed?(org_id, inside)
      refute Security.ip_allowed?(org_id, outside)
    end

    test "reflects updates immediately (cache busted on save)", %{org_id: org_id} do
      # Prime the cache with an empty (allow-all) allowlist.
      assert Security.ip_allowed?(org_id, {203, 0, 113, 5})

      {:ok, _} = Security.update_settings(org_id, %{ip_allowlist: ["10.0.0.0/8"]})

      refute Security.ip_allowed?(org_id, {203, 0, 113, 5})
      assert Security.ip_allowed?(org_id, {10, 0, 0, 1})
    end
  end
end
