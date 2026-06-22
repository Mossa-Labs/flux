defmodule FluxWeb.API.PipelineControllerTest do
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

  defp pipeline(org_id, name) do
    {:ok, p} =
      Pipelines.create_pipeline(%{
        "name" => name,
        "source_queue" => "q",
        "organization_id" => org_id,
        "steps" => %{"version" => "1.0", "steps" => []}
      })

    p
  end

  setup %{conn: conn} do
    o = org()
    other = org("Other")
    %{conn: put_req_header(conn, "content-type", "application/json"), org: o, other: other}
  end

  describe "authentication" do
    test "401 without a key", %{conn: conn} do
      assert conn |> get(~p"/api/pipelines") |> json_response(401)
    end

    test "401 with an invalid key", %{conn: conn} do
      assert conn |> auth("flux_pk_bogus") |> get(~p"/api/pipelines") |> json_response(401)
    end
  end

  describe "index" do
    test "lists only the key's organization pipelines", %{conn: conn, org: o, other: other} do
      pipeline(o.id, "a")
      pipeline(o.id, "b")
      pipeline(other.id, "elsewhere")

      body = conn |> auth(key(o.id, "viewer")) |> get(~p"/api/pipelines") |> json_response(200)
      names = Enum.map(body["data"], & &1["name"]) |> Enum.sort()
      assert names == ["a", "b"]

      assert [%{"sink_count" => _, "status" => _, "source_queue" => _}] =
               Enum.take(body["data"], 1)
    end
  end

  describe "show" do
    test "returns full detail", %{conn: conn, org: o} do
      p = pipeline(o.id, "p")

      body =
        conn |> auth(key(o.id, "viewer")) |> get(~p"/api/pipelines/#{p.id}") |> json_response(200)

      assert body["data"]["id"] == p.id
      assert body["data"]["steps"] == %{"version" => "1.0", "steps" => []}
    end

    test "404 for another org's pipeline", %{conn: conn, org: o, other: other} do
      p = pipeline(other.id, "secret")

      assert conn
             |> auth(key(o.id, "admin"))
             |> get(~p"/api/pipelines/#{p.id}")
             |> json_response(404)
    end

    test "404 for an unknown id", %{conn: conn, org: o} do
      assert conn
             |> auth(key(o.id, "admin"))
             |> get(~p"/api/pipelines/999999")
             |> json_response(404)
    end
  end

  describe "create" do
    test "201 for an admin key and forces organization from the key", %{
      conn: conn,
      org: o,
      other: other
    } do
      params = %{"name" => "new", "source_queue" => "q", "organization_id" => other.id}

      body =
        conn |> auth(key(o.id, "admin")) |> post(~p"/api/pipelines", params) |> json_response(201)

      assert body["data"]["name"] == "new"
      # organization_id from the key wins over the body value
      assert Pipelines.get_pipeline(body["data"]["id"], o.id)
      refute Pipelines.get_pipeline(body["data"]["id"], other.id)
    end

    test "403 for a viewer key", %{conn: conn, org: o} do
      params = %{"name" => "x", "source_queue" => "q"}

      assert conn
             |> auth(key(o.id, "viewer"))
             |> post(~p"/api/pipelines", params)
             |> json_response(403)
    end

    test "422 for invalid params", %{conn: conn, org: o} do
      body =
        conn
        |> auth(key(o.id, "admin"))
        |> post(~p"/api/pipelines", %{"name" => "x"})
        |> json_response(422)

      assert body["details"]["source_queue"]
    end
  end

  describe "start/stop authorization" do
    test "403 for a viewer key", %{conn: conn, org: o} do
      p = pipeline(o.id, "p")

      assert conn
             |> auth(key(o.id, "viewer"))
             |> post(~p"/api/pipelines/#{p.id}/start")
             |> json_response(403)

      assert conn
             |> auth(key(o.id, "viewer"))
             |> post(~p"/api/pipelines/#{p.id}/stop")
             |> json_response(403)
    end

    test "404 for an unknown id", %{conn: conn, org: o} do
      assert conn
             |> auth(key(o.id, "admin"))
             |> post(~p"/api/pipelines/999999/start")
             |> json_response(404)
    end
  end

  describe "export" do
    test "200 returns the portable envelope with a download header", %{conn: conn, org: o} do
      p = pipeline(o.id, "exportable")

      resp = conn |> auth(key(o.id, "viewer")) |> get(~p"/api/pipelines/#{p.id}/export")
      body = json_response(resp, 200)

      assert body["flux_export"] == "1.0"
      assert body["pipeline"]["name"] == "exportable"
      refute Map.has_key?(body["pipeline"], "sink_ids")
      assert [disposition] = get_resp_header(resp, "content-disposition")
      assert disposition =~ "exportable.flux.json"
    end

    test "404 for another org's pipeline", %{conn: conn, org: o, other: other} do
      p = pipeline(other.id, "elsewhere")

      assert conn
             |> auth(key(o.id, "viewer"))
             |> get(~p"/api/pipelines/#{p.id}/export")
             |> json_response(404)
    end
  end

  describe "import" do
    test "201 creates a stopped pipeline", %{conn: conn, org: o} do
      body =
        conn
        |> auth(key(o.id, "admin"))
        |> post(~p"/api/pipelines/import", envelope("imported"))
        |> json_response(201)

      assert body["data"]["name"] == "imported"
      assert body["data"]["status"] == "stopped"
    end

    test "422 for an unsupported version", %{conn: conn, org: o} do
      bad = %{"flux_export" => "9.9", "pipeline" => %{"name" => "x", "source_queue" => "q"}}

      body =
        conn
        |> auth(key(o.id, "admin"))
        |> post(~p"/api/pipelines/import", bad)
        |> json_response(422)

      assert body["error"] == "unsupported_version"
    end

    test "422 with a clear message for missing sinks", %{conn: conn, org: o} do
      env = envelope("needs-sinks", %{"sink_names" => ["ghost"]})

      body =
        conn
        |> auth(key(o.id, "admin"))
        |> post(~p"/api/pipelines/import", env)
        |> json_response(422)

      assert body["error"] == "missing_sinks"
      assert body["message"] =~ "ghost"
    end

    test "422 for a name collision", %{conn: conn, org: o} do
      pipeline(o.id, "dup")

      assert conn
             |> auth(key(o.id, "admin"))
             |> post(~p"/api/pipelines/import", envelope("dup"))
             |> json_response(422)
    end

    test "403 for a viewer key", %{conn: conn, org: o} do
      assert conn
             |> auth(key(o.id, "viewer"))
             |> post(~p"/api/pipelines/import", envelope("nope"))
             |> json_response(403)
    end
  end

  defp envelope(name, pipeline_extra \\ %{}) do
    %{
      "flux_export" => "1.0",
      "exported_at" => "2026-01-01T00:00:00Z",
      "pipeline" =>
        Map.merge(
          %{
            "name" => name,
            "source_queue" => "q",
            "steps" => %{"version" => "1.0", "steps" => []}
          },
          pipeline_extra
        )
    }
  end
end
