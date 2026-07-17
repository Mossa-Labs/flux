defmodule FluxWeb.API.AuditLogController do
  @moduledoc """
  REST API for audit logs (read-only), Enterprise-gated (MOS-482).

  Scoped to the authenticated API key's organization. Returns `403` on
  Community/Pro tiers (via `require_feature(:audit_log)`) or without the
  `read:audit_logs` scope.

  ## Query parameters

    * `actor_id`, `action`, `resource_type`, `resource_id` — exact-match filters
    * `from`, `to` — ISO-8601 timestamps bounding `inserted_at`
    * `limit` (default 50, max 200), `offset` (default 0)
  """
  use FluxWeb, :controller

  import FluxWeb.API.Authz, only: [require_feature: 2, require_scope: 2]

  alias Flux.Audit

  action_fallback FluxWeb.API.FallbackController

  @default_limit 50
  @max_limit 200

  def index(conn, params) do
    with :ok <- require_feature(conn, :audit_log),
         :ok <- require_scope(conn, "read:audit_logs") do
      org_id = conn.assigns.current_scope.organization_id
      filters = build_filters(params)
      limit = parse_limit(params["limit"])
      offset = parse_offset(params["offset"])

      entries = Audit.list_logs(org_id, filters: filters, limit: limit, offset: offset)

      render(conn, :index,
        entries: entries,
        total: Audit.count(org_id, filters),
        limit: limit,
        offset: offset
      )
    end
  end

  defp build_filters(params) do
    %{}
    |> put_present(:actor_id, params["actor_id"])
    |> put_present(:action, params["action"])
    |> put_present(:resource_type, params["resource_type"])
    |> put_present(:resource_id, params["resource_id"])
    |> put_present(:from, parse_ts(params["from"]))
    |> put_present(:to, parse_ts(params["to"]))
  end

  defp put_present(map, _key, value) when value in [nil, ""], do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp parse_ts(nil), do: nil

  defp parse_ts(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_ts(_), do: nil

  defp parse_limit(nil), do: @default_limit

  defp parse_limit(value) do
    case Integer.parse(to_string(value)) do
      {n, _} when n > 0 -> min(n, @max_limit)
      _ -> @default_limit
    end
  end

  defp parse_offset(nil), do: 0

  defp parse_offset(value) do
    case Integer.parse(to_string(value)) do
      {n, _} when n >= 0 -> n
      _ -> 0
    end
  end
end
