defmodule FluxWeb.API.PipelineVersionControllerTest do
  use FluxWeb.ConnCase, async: true

  alias Flux.Accounts
  alias Flux.Pipelines
  alias Flux.Structure.Organization

  defp org(name \\ "Acme") do
    Flux.Repo.insert!(%Organization{
      name: name,
      slug: "org-#{System.unique_integer([:positive])}"
    })
  end

  defp key(org_id, role) do
    {:ok, raw, _} = Accounts.create_api_key(org_id, %{name: "#{role} key", role: role})
    raw
  end

  defp auth(conn, raw), do: put_req_header(conn, "x-api-key", raw)

  # Creates a pipeline with two versions (v1 empty, v2 with a filter step).
  defp versioned_pipeline(org_id) do
    {:ok, p} =
      Pipelines.create_pipeline(%{
        "name" => "p",
        "source_queue" => "q",
        "organization_id" => org_id,
        "steps" => %{"version" => "1.0", "steps" => []}
      })

    {:ok, p} =
      Pipelines.update_pipeline(p, %{
        steps: %{
          "version" => "1.0",
          "steps" => [%{"type" => "native", "operation" => "filter", "config" => %{}}]
        }
      })

    p
  end

  setup %{conn: conn} do
    o = org()
    other = org("Other")
    %{conn: put_req_header(conn, "content-type", "application/json"), org: o, other: other}
  end

  describe "index" do
    test "lists versions newest-first for the key's org", %{conn: conn, org: o} do
      p = versioned_pipeline(o.id)

      body =
        conn
        |> auth(key(o.id, "viewer"))
        |> get(~p"/api/pipelines/#{p.id}/versions")
        |> json_response(200)

      assert Enum.map(body["data"], & &1["version"]) == [2, 1]
      assert Enum.all?(body["data"], &Map.has_key?(&1, "change_summary"))
    end

    test "404 for another org's pipeline", %{conn: conn, org: o, other: other} do
      p = versioned_pipeline(other.id)

      assert conn
             |> auth(key(o.id, "viewer"))
             |> get(~p"/api/pipelines/#{p.id}/versions")
             |> json_response(404)
    end
  end

  describe "rollback" do
    test "admin key rolls back and creates a new version", %{conn: conn, org: o} do
      p = versioned_pipeline(o.id)

      body =
        conn
        |> auth(key(o.id, "admin"))
        |> post(~p"/api/pipelines/#{p.id}/rollback", %{"version" => 1})
        |> json_response(200)

      assert body["data"]["current_version"] == 3
      assert body["data"]["steps"] == %{"version" => "1.0", "steps" => []}
    end

    test "403 for a viewer key", %{conn: conn, org: o} do
      p = versioned_pipeline(o.id)

      assert conn
             |> auth(key(o.id, "viewer"))
             |> post(~p"/api/pipelines/#{p.id}/rollback", %{"version" => 1})
             |> json_response(403)
    end

    test "422 when version is missing", %{conn: conn, org: o} do
      p = versioned_pipeline(o.id)

      assert conn
             |> auth(key(o.id, "admin"))
             |> post(~p"/api/pipelines/#{p.id}/rollback", %{})
             |> json_response(422)
    end

    test "404 for an unknown version", %{conn: conn, org: o} do
      p = versioned_pipeline(o.id)

      assert conn
             |> auth(key(o.id, "admin"))
             |> post(~p"/api/pipelines/#{p.id}/rollback", %{"version" => 99})
             |> json_response(404)
    end
  end
end
