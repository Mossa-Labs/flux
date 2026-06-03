defmodule Flux.LicenseTestProvider do
  @moduledoc """
  Test-only license provider. Reports the tier stored in
  `config :flux, :test_license_tier` (default `:community`).

  It deliberately does NOT override `entitled?/1`, so entitlement flows
  through the real `Flux.License` → `Flux.License.Features` resolution path —
  the same path a production provider uses. Drive it with
  `Flux.LicenseHelpers.with_license_tier/2`.
  """

  @behaviour Flux.License.Provider

  @impl Flux.License.Provider
  def tier, do: Application.get_env(:flux, :test_license_tier, :community)

  @impl Flux.License.Provider
  def fetch do
    tier = tier()

    {:ok,
     %{
       tier: tier,
       features: Flux.License.Features.for_tier(tier),
       org: "Test Org",
       valid_until: nil,
       node_count: nil
     }}
  end
end
