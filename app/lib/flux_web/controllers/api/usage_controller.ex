defmodule FluxWeb.API.UsageController do
  @moduledoc """
  REST API for per-organization usage metering (read-only), scoped to the
  authenticated API key's organization.

  Usage metering is a Pro feature: the endpoint is gated behind
  `:usage_metering`, so the Community tier receives `403 Forbidden`. The actual
  usage figures come from the active `Flux.Metering` provider (the commercial
  edition overlays a real provider; Community resolves to a zeroed stub).
  """
  use FluxWeb, :controller

  import FluxWeb.API.Authz, only: [require_scope: 2, require_feature: 2]

  action_fallback FluxWeb.API.FallbackController

  def show(conn, _params) do
    org_id = conn.assigns.current_scope.organization_id

    with :ok <- require_scope(conn, "read:usage"),
         :ok <- require_feature(conn, :usage_metering),
         {:ok, usage} <- Flux.Metering.get_usage(org_id) do
      render(conn, :show, usage: usage)
    end
  end
end
