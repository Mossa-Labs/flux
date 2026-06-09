defmodule Flux.Pipeline.ManagerStartLimitTest do
  @moduledoc """
  MOS-450: user-initiated pipeline starts are capped per org and node-wide. The
  bucket is pre-filled via Flux.RateLimiter so the Manager's own check is the one
  that trips — exercising the rejection path without spawning real pipelines.
  """
  # async: false — shared sandbox (the Manager process reads the DB) + global config.
  use Flux.DataCase, async: false

  alias Flux.Pipeline.Manager
  alias Flux.Structure.Organization

  setup do
    prev = Application.get_env(:flux, Manager)
    Flux.RateLimiter.reset()

    on_exit(fn ->
      if prev,
        do: Application.put_env(:flux, Manager, prev),
        else: Application.delete_env(:flux, Manager)

      Flux.RateLimiter.reset()
    end)

    :ok
  end

  defp org,
    do:
      Repo.insert!(%Organization{
        name: "Acme",
        slug: "org-#{System.unique_integer([:positive])}"
      })

  defp stopped_pipeline(org_id) do
    {:ok, p} =
      Flux.Pipelines.create_pipeline(%{
        "name" => "p-#{System.unique_integer([:positive])}",
        "source_queue" => "q",
        "organization_id" => org_id
      })

    p
  end

  test "rejects starts over the per-org limit" do
    Application.put_env(:flux, Manager,
      start_limit: 3,
      start_node_limit: 1_000,
      start_window_ms: 60_000
    )

    o = org()
    p = stopped_pipeline(o.id)

    # Fill the per-org bucket to its limit; the Manager's check is then over.
    for _ <- 1..3, do: assert(Flux.RateLimiter.allow?({:pipeline_start, o.id}, 3, 60_000))

    assert Manager.start_pipeline(p.id) == {:error, :rate_limited}
  end

  test "rejects starts over the node-wide ceiling" do
    Application.put_env(:flux, Manager,
      start_limit: 1_000,
      start_node_limit: 2,
      start_window_ms: 60_000
    )

    o = org()
    p = stopped_pipeline(o.id)

    # Per-org budget is generous; the node ceiling is what trips.
    for _ <- 1..2, do: assert(Flux.RateLimiter.allow?(:pipeline_start_node, 2, 60_000))

    assert Manager.start_pipeline(p.id) == {:error, :rate_limited}
  end
end
