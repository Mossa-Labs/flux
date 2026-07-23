defmodule FluxWeb.Plugs.IpAllowlist do
  @moduledoc """
  Per-org IP allowlist for the authenticated API (MOS-588).

  When an organization has configured an IP allowlist, requests whose client IP
  falls outside every allowed CIDR range are rejected with `403 Forbidden`. An
  empty allowlist (the default) allows all IPs, so this is opt-in per org.

  Must run AFTER `FluxWeb.Plugs.ApiAuth` in the `:api_authenticated` pipeline, so
  `current_scope.organization_id` is known. Relies on `conn.remote_ip` being the
  real client IP — see `FluxWeb.Plugs.ClientIp`. The allow/deny decision and its
  cache live in `Flux.Security`.

  **Scope:** this covers the whole authenticated API surface, including webhook
  ingestion — an org that sets an allowlist must include its webhook sources.
  UI access is never IP-restricted, so an owner can always reach the settings.
  """

  import Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case org_id(conn) do
      nil -> conn
      org_id -> enforce(conn, org_id)
    end
  end

  defp enforce(conn, org_id) do
    if Flux.Security.ip_allowed?(org_id, conn.remote_ip) do
      conn
    else
      :telemetry.execute([:flux, :api, :ip_blocked], %{count: 1}, %{
        organization_id: org_id,
        remote_ip: conn.remote_ip
      })

      conn
      |> put_status(:forbidden)
      |> Phoenix.Controller.json(%{
        error: "ip_not_allowed",
        message: "Your IP address is not permitted to access this API."
      })
      |> halt()
    end
  end

  defp org_id(conn) do
    case conn.assigns[:current_scope] do
      %{organization_id: org_id} -> org_id
      _ -> nil
    end
  end
end
