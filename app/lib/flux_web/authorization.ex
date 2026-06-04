defmodule FluxWeb.Authorization do
  @moduledoc """
  Authorization helpers for LiveViews.

  Gates privileged events through `Flux.Permissions` so the UI enforces the same
  rules as the REST API, and lets templates hide controls the current user
  cannot use. Import into a LiveView and wrap mutating handlers with
  `authorize/3`; use `can?/2` in templates to conditionally render controls.
  """

  import Phoenix.LiveView, only: [put_flash: 3]

  alias Flux.Accounts.Scope
  alias Flux.Permissions

  @deny_message "You don't have permission to do that."

  @doc "Whether the current scope (from a socket or a `Scope`) may perform `action`."
  def can?(%Phoenix.LiveView.Socket{assigns: %{current_scope: scope}}, action),
    do: Permissions.can?(scope, action)

  def can?(%Scope{} = scope, action), do: Permissions.can?(scope, action)
  def can?(_other, _action), do: false

  @doc """
  Runs `fun` when the current scope may perform `action`; otherwise returns
  `{:noreply, socket}` with an error flash and performs no mutation. `fun` is a
  zero-arity function returning the handler's `{:noreply, socket}` result.
  """
  def authorize(socket, action, fun) when is_function(fun, 0) do
    if can?(socket, action) do
      fun.()
    else
      {:noreply, put_flash(socket, :error, @deny_message)}
    end
  end
end
