defmodule FluxWeb.API.SinkControllerTest do
  use FluxWeb.ConnCase, async: true

  alias Flux.Accounts
  alias Flux.Sinks
  alias Flux.Structure.Organization

  defp org(name \\ "Acme") do
    Flux.Repo.insert!(%Organization{
      name: name,
      slug: "org-#{System.unique_integer([:positive])}"
    })
  end

  defp key(org_id) do
    {:ok, raw, _} = Accounts.create_api_key(org_id, %{name: "k", role: "viewer"})
    raw
  end

  defp auth(conn, raw), do: put_req_header(conn, "x-api-key", raw)

  setup %{conn: conn} do
    %{conn: put_req_header(conn, "content-type", "application/json")}
  end

  test "401 without a key", %{conn: conn} do
    assert conn |> get(~p"/api/sinks") |> json_response(401)
  end

  test "403 when the key lacks the read:sinks scope", %{conn: conn} do
    o = org()

    {:ok, raw, _} =
      Accounts.create_api_key(o.id, %{name: "k", role: "admin", scopes: ["read:pipelines"]})

    assert conn |> auth(raw) |> get(~p"/api/sinks") |> json_response(403)
  end

  test "lists the org's sinks with secrets redacted", %{conn: conn} do
    o = org()
    other = org("Other")

    {:ok, _} =
      Sinks.create_sink(%{
        "name" => "webhook",
        "type" => "http",
        "organization_id" => o.id,
        "config" => %{
          "url" => "https://x",
          "auth" => %{"type" => "bearer", "token" => "supersecret"}
        }
      })

    {:ok, _} =
      Sinks.create_sink(%{
        "name" => "elsewhere",
        "type" => "http",
        "organization_id" => other.id,
        "config" => %{"url" => "https://y"}
      })

    body = conn |> auth(key(o.id)) |> get(~p"/api/sinks") |> json_response(200)

    assert [sink] = body["data"]
    assert sink["name"] == "webhook"
    assert sink["config"]["auth"]["token"] == "[REDACTED]"
    assert sink["config"]["url"] == "https://x"
  end
end
