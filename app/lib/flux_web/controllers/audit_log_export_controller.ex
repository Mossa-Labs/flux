defmodule FluxWeb.AuditLogExportController do
  @moduledoc """
  Streams an audit-log export (CSV or JSON) as a file download (MOS-482).

  Owner-only and Enterprise-gated; mirrors the filters accepted by the audit
  viewer. A LiveView cannot stream a file directly, so the viewer links here.
  """
  use FluxWeb, :controller

  alias Flux.Audit

  def export(conn, params) do
    scope = conn.assigns.current_scope

    cond do
      not (scope && Flux.Permissions.can?(scope, :view_audit_log)) ->
        conn |> put_status(:forbidden) |> text("Forbidden")

      true ->
        format = normalize_format(params["format"])
        filters = build_filters(params)

        case Audit.export_logs(scope.organization_id, format, filters: filters) do
          {:ok, data} ->
            send_export(conn, format, data)

          {:error, _} ->
            conn
            |> put_status(:forbidden)
            |> text("Audit log export requires an Enterprise license.")
        end
    end
  end

  defp send_export(conn, :csv, data) do
    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="audit-logs.csv"))
    |> send_resp(200, data)
  end

  defp send_export(conn, :json, data) do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("content-disposition", ~s(attachment; filename="audit-logs.json"))
    |> send_resp(200, data)
  end

  defp normalize_format("json"), do: :json
  defp normalize_format(_), do: :csv

  defp build_filters(params) do
    %{}
    |> put_present(:actor_id, params["actor_id"])
    |> put_present(:action, params["action"])
    |> put_present(:resource_type, params["resource_type"])
    |> put_present(:from, parse_dt(params["from"]))
    |> put_present(:to, parse_dt(params["to"]))
  end

  defp put_present(map, _key, value) when value in [nil, ""], do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  # Accept both datetime-local (naive, UTC) and ISO-8601 inputs.
  defp parse_dt(nil), do: nil
  defp parse_dt(""), do: nil

  defp parse_dt(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} ->
        dt

      _ ->
        case NaiveDateTime.from_iso8601(pad_seconds(value)) do
          {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
          _ -> nil
        end
    end
  end

  defp pad_seconds(str) do
    case String.split(str, ":") do
      [_h, _m] -> str <> ":00"
      _ -> str
    end
  end
end
