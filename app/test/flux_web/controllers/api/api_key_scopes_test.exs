defmodule FluxWeb.API.ApiKeyScopesTest do
  @moduledoc """
  Fine-grained (below-role) API key scopes are a Pro feature (`:api_key_scopes`).
  Without the entitlement, requested scopes are ignored and a key falls back to
  its role's full set; with it, scopes restrict the key and are enforced.
  """
  # async: false — with_license_tier/2 swaps the global license provider.
  use FluxWeb.ConnCase, async: false

  import Flux.LicenseHelpers

  alias Flux.Accounts
  alias Flux.Accounts.ApiKey
  alias Flux.Structure.Organization

  defp org,
    do:
      Flux.Repo.insert!(%Organization{
        name: "Acme",
        slug: "org-#{System.unique_integer([:positive])}"
      })

  defp auth(conn, raw), do: put_req_header(conn, "x-api-key", raw)

  setup %{conn: conn} do
    %{conn: put_req_header(conn, "content-type", "application/json"), org: org()}
  end

  describe "without the :api_key_scopes entitlement (Community)" do
    test "requested scopes are ignored and fall back to the role's full set", %{org: o} do
      {:ok, _raw, key} =
        Accounts.create_api_key(o.id, %{name: "k", role: "admin", scopes: ["read:pipelines"]})

      assert Enum.sort(key.scopes) == Enum.sort(ApiKey.scopes())
    end

    test "a key requested as read-only can still create (restriction not applied)", %{
      conn: conn,
      org: o
    } do
      {:ok, raw, _} =
        Accounts.create_api_key(o.id, %{name: "k", role: "admin", scopes: ["read:pipelines"]})

      assert conn
             |> auth(raw)
             |> post(~p"/api/pipelines", %{"name" => "p", "source_queue" => "q"})
             |> json_response(201)
    end
  end

  describe "with the :api_key_scopes entitlement (Pro)" do
    test "scopes are honored and stored as given" do
      o = org()

      with_license_tier(:pro, fn ->
        {:ok, _raw, key} =
          Accounts.create_api_key(o.id, %{name: "k", role: "admin", scopes: ["read:pipelines"]})

        assert key.scopes == ["read:pipelines"]
      end)
    end

    test "unknown scopes are rejected" do
      o = org()

      with_license_tier(:pro, fn ->
        assert {:error, %Ecto.Changeset{} = cs} =
                 Accounts.create_api_key(o.id, %{name: "k", scopes: ["read:everything"]})

        assert Keyword.has_key?(cs.errors, :scopes)
      end)
    end

    test "a read-only-scoped key can list but not create, and is denied sinks", %{
      conn: conn,
      org: o
    } do
      raw =
        with_license_tier(:pro, fn ->
          {:ok, raw, _} =
            Accounts.create_api_key(o.id, %{name: "k", role: "admin", scopes: ["read:pipelines"]})

          raw
        end)

      # Enforcement is always-on (no license needed at request time).
      assert conn |> auth(raw) |> get(~p"/api/pipelines") |> json_response(200)

      assert conn
             |> auth(raw)
             |> post(~p"/api/pipelines", %{"name" => "x", "source_queue" => "q"})
             |> json_response(403)

      assert conn |> auth(raw) |> get(~p"/api/sinks") |> json_response(403)
    end
  end
end
