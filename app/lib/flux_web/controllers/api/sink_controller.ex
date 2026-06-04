defmodule FluxWeb.API.SinkController do
  @moduledoc """
  REST API for sinks (read-only). Scoped to the authenticated API key's
  organization; secret config fields are redacted in responses.
  """
  use FluxWeb, :controller

  import FluxWeb.API.Authz, only: [require_scope: 2]

  alias Flux.Sinks

  action_fallback FluxWeb.API.FallbackController

  def index(conn, _params) do
    with :ok <- require_scope(conn, "read:sinks") do
      sinks = Sinks.list_sinks(conn.assigns.current_scope.organization_id)
      render(conn, :index, sinks: sinks)
    end
  end
end
