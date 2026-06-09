defmodule FluxWeb.API.UsageControllerTest do
  @moduledoc """
  `GET /api/usage` is gated behind the `:usage_metering` Pro feature: Community
  receives `403`, Pro receives the active provider's usage data.
  """
  # async: false — with_license_tier/2 and the metering registry are global.
  use FluxWeb.ConnCase, async: false

  import Flux.LicenseHelpers

  alias Flux.Accounts
  alias Flux.Structure.Organization

  defp org,
    do:
      Flux.Repo.insert!(%Organization{
        name: "Acme",
        slug: "org-#{System.unique_integer([:positive])}"
      })

  defp key(org_id) do
    {:ok, raw, _} = Accounts.create_api_key(org_id, %{name: "k", role: "viewer"})
    raw
  end

  defp auth(conn, raw), do: put_req_header(conn, "x-api-key", raw)

  setup %{conn: conn} do
    %{conn: put_req_header(conn, "content-type", "application/json"), org: org()}
  end

  test "401 without a key", %{conn: conn} do
    assert conn |> get(~p"/api/usage") |> json_response(401)
  end

  test "403 on Community (no :usage_metering entitlement)", %{conn: conn, org: o} do
    raw = key(o.id)
    assert conn |> auth(raw) |> get(~p"/api/usage") |> json_response(403)
  end

  test "200 with usage data on Pro", %{conn: conn, org: o} do
    raw = key(o.id)
    Flux.Metering.Registry.set_active(Flux.MeteringTestProvider)
    on_exit(fn -> Flux.Metering.Registry.set_active(Flux.Metering.Providers.Community) end)

    with_license_tier(:pro, fn ->
      body = conn |> auth(raw) |> get(~p"/api/usage") |> json_response(200)

      assert %{
               "data" => %{
                 "metrics" => %{"messages_ingested" => 1_234},
                 "quota" => %{"limit" => 10_000}
               }
             } = body
    end)
  end
end
