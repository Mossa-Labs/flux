defmodule FluxWeb.API.Authz do
  @moduledoc """
  Authorization helper for API controllers. Evaluates the request's
  `current_scope` (assigned by `FluxWeb.Plugs.ApiAuth` from the API key) against
  `Flux.Permissions`. Returns `:ok` or `{:error, :forbidden}`, which the
  `FallbackController` renders as `403`.
  """

  alias Flux.Permissions

  @spec authorize(Plug.Conn.t(), atom()) :: :ok | {:error, :forbidden}
  def authorize(%Plug.Conn{assigns: %{current_scope: scope}}, action) do
    if Permissions.can?(scope, action), do: :ok, else: {:error, :forbidden}
  end

  def authorize(%Plug.Conn{}, _action), do: {:error, :forbidden}
end
