defmodule FluxWeb.API.HealthController do
  @moduledoc """
  Unauthenticated health probe for load balancers: checks database and queue
  connectivity and reports the app version. Returns `200` when healthy, `503`
  otherwise.
  """
  use FluxWeb, :controller

  def show(conn, _params) do
    database = check_database()
    queue = check_queue()
    healthy? = database == "connected" and queue == "connected"

    conn
    |> put_status(if healthy?, do: :ok, else: :service_unavailable)
    |> json(%{
      status: if(healthy?, do: "ok", else: "degraded"),
      database: database,
      queue: queue,
      version: version(),
      cluster: cluster_info()
    })
  end

  defp cluster_info do
    nodes = [node() | Node.list()]

    %{
      node: to_string(node()),
      node_count: length(nodes),
      nodes: Enum.map(nodes, &to_string/1),
      supervisor_members: supervisor_member_count()
    }
  end

  # Number of nodes participating in pipeline supervision. The Community
  # (single-node) backend reports 1; the Pro distributed backend reports the
  # cluster member count. Falls back to 1 on error.
  defp supervisor_member_count do
    Flux.Pipeline.Supervision.member_count()
  rescue
    _ -> 1
  end

  defp check_database do
    case Ecto.Adapters.SQL.query(Flux.Repo, "SELECT 1", []) do
      {:ok, _} -> "connected"
      _ -> "disconnected"
    end
  rescue
    _ -> "disconnected"
  end

  defp check_queue do
    case Flux.Queue.Registry.active() do
      {:ok, _adapter} -> "connected"
      _ -> "disconnected"
    end
  end

  defp version do
    case Application.spec(:flux, :vsn) do
      nil -> "unknown"
      vsn -> to_string(vsn)
    end
  end
end
