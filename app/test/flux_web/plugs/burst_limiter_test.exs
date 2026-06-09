defmodule FluxWeb.Plugs.BurstLimiterTest do
  # async: false — mutates the global BurstLimiter config + shared limiter table.
  use FluxWeb.ConnCase, async: false

  alias Flux.Accounts
  alias Flux.Structure.Organization

  setup %{conn: conn} do
    prev = Application.get_env(:flux, FluxWeb.Plugs.BurstLimiter)
    Application.put_env(:flux, FluxWeb.Plugs.BurstLimiter, limit: 2, window_ms: 60_000)
    Flux.RateLimiter.reset()

    on_exit(fn ->
      if prev,
        do: Application.put_env(:flux, FluxWeb.Plugs.BurstLimiter, prev),
        else: Application.delete_env(:flux, FluxWeb.Plugs.BurstLimiter)

      Flux.RateLimiter.reset()
    end)

    %{conn: put_req_header(conn, "content-type", "application/json")}
  end

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

  defp request(raw), do: build_conn() |> put_req_header("x-api-key", raw) |> get(~p"/api/sinks")

  test "permits up to the limit, then returns 429 + Retry-After" do
    raw = key(org().id)

    assert json_response(request(raw), 200)
    assert json_response(request(raw), 200)

    over = request(raw)
    assert json_response(over, 429)["error"] == "rate_limited"
    assert get_resp_header(over, "retry-after") == ["1"]
  end

  test "limits are per API key" do
    raw_a = key(org().id)
    raw_b = key(org().id)

    assert json_response(request(raw_a), 200)
    assert json_response(request(raw_a), 200)
    assert json_response(request(raw_a), 429)

    # A different key still has its full budget.
    assert json_response(request(raw_b), 200)
  end

  test "emits [:flux, :api, :burst_limited] telemetry on a breach" do
    raw = key(org().id)
    ref = make_ref()
    parent = self()

    :telemetry.attach(
      "test-burst-#{inspect(ref)}",
      [:flux, :api, :burst_limited],
      fn _event, measurements, metadata, _ ->
        send(parent, {:burst, ref, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach("test-burst-#{inspect(ref)}") end)

    for _ <- 1..3, do: request(raw)

    assert_receive {:burst, ^ref, %{count: 1}, %{organization_id: _}}
  end
end
