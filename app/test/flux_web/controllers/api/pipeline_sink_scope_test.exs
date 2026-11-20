defmodule FluxWeb.API.PipelineSinkScopeTest do
  use FluxWeb.ConnCase, async: true

  import Flux.SinksFixtures

  alias Flux.Accounts
  alias Flux.Structure.Organization

  test "POST /api/pipelines refuses another organization's sink", %{conn: conn} do
    org = org()
    foreign_sink = sink_fixture(org().id)
    {:ok, raw, _} = Accounts.create_api_key(org.id, %{name: "admin key", role: "admin"})

    params = %{
      "name" => "exfil",
      "source_queue" => "q",
      "sink_ids" => [foreign_sink.id],
      "steps" => %{"version" => "1.0", "steps" => []}
    }

    body =
      conn
      |> put_req_header("x-api-key", raw)
      |> post(~p"/api/pipelines", params)
      |> json_response(422)

    assert %{"details" => %{"sink_ids" => [_]}} = body
    assert Flux.Pipelines.list_pipelines(org.id) == []
  end

  defp org do
    Flux.Repo.insert!(%Organization{
      name: "Org #{System.unique_integer([:positive])}",
      slug: "org-#{System.unique_integer([:positive])}"
    })
  end
end
