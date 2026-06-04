defmodule FluxWeb.Plugs.ApiAuth do
  @moduledoc """
  Authenticates API requests via the `X-API-Key` header and assigns
  `conn.assigns.current_scope` for downstream org-scoping and authorization.

  Resolution order:

    1. **Per-organization key** (`flux_pk_...`) — looked up in `api_keys`; the
       scope's org and role come from the key. Usage is recorded off the
       request path.
    2. **Legacy global key** (`config :flux, FluxWeb.Plugs.ApiAuth, api_key:`) —
       kept for backwards compatibility during migration; scoped to the first
       organization with the `owner` role and logged as deprecated.

  Anything else (missing/invalid/revoked/expired) returns `401`.

  ## Usage

      pipeline :api_authenticated do
        plug :accepts, ["json"]
        plug FluxWeb.Plugs.ApiAuth
      end
  """

  import Plug.Conn
  import Ecto.Query, only: [from: 2]

  require Logger

  alias Flux.Accounts
  alias Flux.Accounts.{ApiKey, ApiKeyUsage, Scope}
  alias Flux.Repo
  alias Flux.Structure.Organization

  @behaviour Plug

  @per_org_prefix "flux_pk_"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case get_api_key(conn) do
      {:ok, key} ->
        authenticate(conn, key)

      {:error, :missing_key} ->
        unauthorized(conn, "Missing API key", "X-API-Key header is required")
    end
  end

  defp authenticate(conn, @per_org_prefix <> _ = raw) do
    case Accounts.authenticate_api_key(raw) do
      {:ok, api_key} ->
        ApiKeyUsage.touch(api_key.id)

        :telemetry.execute([:flux, :api, :authenticated], %{}, %{
          api_key_id: api_key.id,
          organization_id: api_key.organization_id
        })

        conn
        |> assign(:current_scope, %Scope{
          user: nil,
          organization_id: api_key.organization_id,
          organization_role: api_key.role
        })
        |> assign(:api_scopes, ApiKey.effective_scopes(api_key))

      {:error, :unauthorized} ->
        unauthorized(
          conn,
          "Invalid API key",
          "The provided API key is invalid, revoked, or expired"
        )
    end
  end

  defp authenticate(conn, raw) do
    case Application.get_env(:flux, __MODULE__)[:api_key] do
      configured when is_binary(configured) and configured != "" ->
        if Plug.Crypto.secure_compare(raw, configured),
          do: legacy_scope(conn),
          else: unauthorized(conn, "Invalid API key", "The provided API key is invalid")

      _ ->
        unauthorized(conn, "Invalid API key", "The provided API key is invalid")
    end
  end

  defp legacy_scope(conn) do
    Logger.warning(
      "[ApiAuth] Authenticated with the deprecated global API key. Migrate to a per-organization key (flux_pk_...)."
    )

    org_id =
      Repo.one(from(o in Organization, order_by: [asc: o.inserted_at], limit: 1, select: o.id))

    :telemetry.execute([:flux, :api, :authenticated], %{}, %{
      api_key_id: nil,
      organization_id: org_id
    })

    conn
    |> assign(:current_scope, %Scope{
      user: nil,
      organization_id: org_id,
      organization_role: "owner"
    })
    |> assign(:api_scopes, ApiKey.scopes())
  end

  defp get_api_key(conn) do
    case get_req_header(conn, "x-api-key") do
      [key | _] when byte_size(key) > 0 -> {:ok, key}
      _ -> {:error, :missing_key}
    end
  end

  defp unauthorized(conn, error, message) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{error: error, message: message})
    |> halt()
  end
end
