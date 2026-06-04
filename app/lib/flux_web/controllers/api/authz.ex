defmodule FluxWeb.API.Authz do
  @moduledoc """
  Authorization helpers for API controllers, both returning `:ok` or
  `{:error, :forbidden}` (rendered as `403` by the `FallbackController`):

    * `authorize/2` — the request's `current_scope` (org role) against
      `Flux.Permissions`;
    * `require_scope/2` — the API key's granted `scopes` against the scope an
      endpoint needs.

  A mutating endpoint checks both, so a key is bounded by its role *and* its
  scopes.
  """

  alias Flux.Permissions

  @spec authorize(Plug.Conn.t(), atom()) :: :ok | {:error, :forbidden}
  def authorize(%Plug.Conn{assigns: %{current_scope: scope}}, action) do
    if Permissions.can?(scope, action), do: :ok, else: {:error, :forbidden}
  end

  def authorize(%Plug.Conn{}, _action), do: {:error, :forbidden}

  @spec require_scope(Plug.Conn.t(), String.t()) :: :ok | {:error, :forbidden}
  def require_scope(%Plug.Conn{assigns: %{api_scopes: scopes}}, scope) when is_list(scopes) do
    if scope in scopes, do: :ok, else: {:error, :forbidden}
  end

  def require_scope(%Plug.Conn{}, _scope), do: {:error, :forbidden}
end
