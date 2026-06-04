defmodule Flux.Accounts.ApiKeyTest do
  use Flux.DataCase, async: true

  alias Flux.Accounts
  alias Flux.Accounts.ApiKey
  alias Flux.Structure.Organization

  defp org do
    Repo.insert!(%Organization{name: "Acme", slug: "acme-#{System.unique_integer([:positive])}"})
  end

  describe "create_api_key/2" do
    test "returns a plaintext key once and stores only its hash" do
      o = org()

      assert {:ok, raw, %ApiKey{} = key} =
               Accounts.create_api_key(o.id, %{name: "CI", role: "admin"})

      assert String.starts_with?(raw, "flux_pk_")
      assert key.organization_id == o.id
      assert key.role == "admin"
      assert key.key_hash == Accounts.hash_api_key(raw)
      refute key.key_hash == raw
      assert String.starts_with?(key.key_prefix, "flux_pk_")
    end

    test "defaults role to admin and requires a name" do
      o = org()
      assert {:ok, _raw, key} = Accounts.create_api_key(o.id, %{name: "no-role"})
      assert key.role == "admin"
      assert {:error, changeset} = Accounts.create_api_key(o.id, %{name: nil})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects an unknown role" do
      o = org()
      assert {:error, changeset} = Accounts.create_api_key(o.id, %{name: "x", role: "root"})
      assert %{role: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "authenticate_api_key/1" do
    test "accepts a valid active key" do
      o = org()
      {:ok, raw, key} = Accounts.create_api_key(o.id, %{name: "k"})
      assert {:ok, found} = Accounts.authenticate_api_key(raw)
      assert found.id == key.id
    end

    test "rejects an unknown key" do
      assert {:error, :unauthorized} = Accounts.authenticate_api_key("flux_pk_nope")
    end

    test "rejects a revoked key" do
      o = org()
      {:ok, raw, key} = Accounts.create_api_key(o.id, %{name: "k"})
      {:ok, _} = Accounts.revoke_api_key(key)
      assert {:error, :unauthorized} = Accounts.authenticate_api_key(raw)
    end

    test "rejects an expired key" do
      o = org()
      past = DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.truncate(:second)
      {:ok, raw, _key} = Accounts.create_api_key(o.id, %{name: "k", expires_at: past})
      assert {:error, :unauthorized} = Accounts.authenticate_api_key(raw)
    end
  end

  test "list_api_keys/1 is org-scoped" do
    a = org()
    b = org()
    {:ok, _, _} = Accounts.create_api_key(a.id, %{name: "a"})
    {:ok, _, _} = Accounts.create_api_key(b.id, %{name: "b"})

    assert [%ApiKey{name: "a"}] = Accounts.list_api_keys(a.id)
  end

  test "touch_api_key/1 stamps last_used_at" do
    o = org()
    {:ok, _raw, key} = Accounts.create_api_key(o.id, %{name: "k"})
    assert key.last_used_at == nil
    assert :ok = Accounts.touch_api_key(key.id)
    assert Repo.reload(key).last_used_at != nil
  end
end
