defmodule Flux.Branding.Providers.Community do
  @moduledoc """
  Community branding: always stock Flux, never customisable.

  Unlike most Community stubs this one is not a no-op — the chrome has to render
  *something*, and stock Flux is the correct something. Only the write paths
  refuse.
  """

  @behaviour Flux.Branding.Provider

  alias Flux.Branding.Theme

  @pro_required {:error, [{:base, "White-label branding requires Flux Enterprise."}]}

  @impl Flux.Branding.Provider
  def theme(_org_id), do: Theme.default()

  @impl Flux.Branding.Provider
  def put(_org_id, _attrs), do: @pro_required

  @impl Flux.Branding.Provider
  def put_asset(_org_id, _kind, _bytes), do: @pro_required

  @impl Flux.Branding.Provider
  def asset(_org_id, _kind), do: :none

  # Community renders stock branding regardless of organization, so there is
  # nothing to look up and no reason to touch the database on the sign-in path.
  @impl Flux.Branding.Provider
  def deployment_org_id, do: nil
end
