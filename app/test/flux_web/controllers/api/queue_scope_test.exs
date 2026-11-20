defmodule FluxWeb.API.QueueScopeTest do
  use FluxWeb.ConnCase, async: true

  alias Flux.Accounts
  alias Flux.Structure.Organization

  setup do
    org = org()
    {:ok, raw, _} = Accounts.create_api_key(org.id, %{name: "admin key", role: "admin"})
    %{org: org, key: raw}
  end

  test "POST /api/pipelines refuses a queue in another organization", %{
    conn: conn,
    org: org,
    key: key
  } do
    victim = org()

    params = %{
      "name" => "exfil",
      "source_queue" => "org.#{victim.id}.webhooks.stripe",
      "steps" => %{"version" => "1.0", "steps" => []}
    }

    body =
      conn
      |> put_req_header("x-api-key", key)
      |> post(~p"/api/pipelines", params)
      |> json_response(422)

    assert %{"details" => %{"source_queue" => [_]}} = body
    assert Flux.Pipelines.list_pipelines(org.id) == []
  end

  test "POST /api/webhooks/:source refuses a source that isn't a queue name segment", %{
    conn: conn,
    key: key
  } do
    for source <- ["bad name", "wild*", "wild#", ".hidden"] do
      body =
        conn
        |> put_req_header("x-api-key", key)
        |> post("/api/webhooks/#{URI.encode(source, &URI.char_unreserved?/1)}", %{"a" => 1})
        |> json_response(400)

      assert body["error"] == "invalid_source"
    end
  end

  defp org do
    Flux.Repo.insert!(%Organization{
      name: "Org #{System.unique_integer([:positive])}",
      slug: "org-#{System.unique_integer([:positive])}"
    })
  end
end
