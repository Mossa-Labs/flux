defmodule FluxWeb.Plugs.Branding do
  @moduledoc """
  Assigns `:branding` for the root layout (MOS-483).

  Runs after `:fetch_current_scope_for_user`, so an authenticated request gets
  its own organization's branding and a signed-out one falls back to the
  deployment's. The root layout receives the conn's assigns, so this is all it
  takes to brand the `<title>`, the icon and the colour override.

  A plug rather than reading the scope directly in the layout: the anonymous
  fallback has to happen somewhere, and the layout should not know that branding
  is scope-derived at all.

  Not added to the `:api` pipeline — nothing there renders chrome.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    Plug.Conn.assign(conn, :branding, Flux.Branding.for_scope(conn.assigns[:current_scope]))
  end
end
