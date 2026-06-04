defmodule FluxWeb.API.PipelineLifecycleTest do
  # async: false — drives the real Manager/Runner (start/stop a Broadway pipeline)
  # which run in app-owned processes; shared sandbox is required.
  use FluxWeb.ConnCase, async: false

  alias Flux.Accounts
  alias Flux.Pipeline.Manager
  alias Flux.Pipelines
  alias Flux.Structure.Organization

  setup %{conn: conn} do
    org =
      Flux.Repo.insert!(%Organization{
        name: "Acme",
        slug: "org-#{System.unique_integer([:positive])}"
      })

    {:ok, raw, _} = Accounts.create_api_key(org.id, %{name: "admin", role: "admin"})

    {:ok, p} =
      Pipelines.create_pipeline(%{
        "name" => "lifecycle",
        "source_queue" => "lifecycle-q",
        "organization_id" => org.id,
        "steps" => %{"version" => "1.0", "steps" => []}
      })

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-api-key", raw)

    on_exit(fn -> Manager.stop_pipeline(p.id) end)

    %{conn: conn, pipeline: p}
  end

  test "start then stop round-trips through the API", %{conn: conn, pipeline: p} do
    started = conn |> post(~p"/api/pipelines/#{p.id}/start") |> json_response(200)
    assert started["data"]["id"] == p.id
    assert started["data"]["status"] == "active"
    assert Manager.get_status(p.id) == :running

    stopped = conn |> post(~p"/api/pipelines/#{p.id}/stop") |> json_response(200)
    assert stopped["data"]["status"] == "stopped"
    assert Manager.get_status(p.id) == :stopped
  end
end
