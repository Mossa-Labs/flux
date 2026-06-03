defmodule Flux.License.Providers.Community do
  @moduledoc """
  Default license provider for public `flux` builds. Always reports the
  `:community` tier. Entitlement is derived by `Flux.License` from this tier
  against `Flux.License.Features` (the community tier grants no Pro/EE
  features), so this module does not override `entitled?/1`.
  """

  @behaviour Flux.License.Provider

  @impl Flux.License.Provider
  def fetch,
    do: {:ok, %{tier: :community, features: [], org: nil, valid_until: nil, node_count: nil}}

  @impl Flux.License.Provider
  def tier, do: :community
end
