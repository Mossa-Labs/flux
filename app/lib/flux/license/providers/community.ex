defmodule Flux.License.Providers.Community do
  @moduledoc """
  Default license provider for public `flux` builds. Always reports the
  `:community` tier and denies entitlement to any Pro/EE feature.
  """

  @behaviour Flux.License.Provider

  @impl Flux.License.Provider
  def fetch, do: {:ok, %{tier: :community, features: [], valid_until: nil}}

  @impl Flux.License.Provider
  def entitled?(_feature), do: false

  @impl Flux.License.Provider
  def tier, do: :community
end
