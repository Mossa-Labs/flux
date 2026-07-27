defmodule Flux.LicenseActivationTestProvider do
  @moduledoc """
  Test provider that supports runtime activation (MOS-451), standing in for the
  commercial edition's provider. Drive its responses via `Application` env:

    * `:test_activation_license` — the map returned by `fetch/0` / used for `tier/0`
      and `status/0` (default: a Pro license with `status: :active`).
    * `:test_activation_result` — the `apply_license/1` return value
      (default: `{:ok, <license>}`).
    * `:test_node_states` — the `node_states/0` list, for exercising the
      cluster-aware UI (default: unset, so the callback is absent and
      `Flux.License.node_states/0` falls back to reporting this node).

  Tests using it MUST be `async: false` (it swaps the global provider config).
  """

  @behaviour Flux.License.Provider

  @default %{
    tier: :pro,
    features: [],
    org: "Acme",
    valid_until: nil,
    node_count: 3,
    status: :active
  }

  @impl Flux.License.Provider
  def fetch, do: {:ok, license_map()}

  @impl Flux.License.Provider
  def tier, do: license_map().tier

  @impl Flux.License.Provider
  def apply_license(_token),
    do: Application.get_env(:flux, :test_activation_result, {:ok, license_map()})

  defp license_map, do: Application.get_env(:flux, :test_activation_license, @default)

  # Only answers when a test opts in, so the default provider still exercises the
  # single-node fallback in `Flux.License.node_states/0`.
  @impl Flux.License.Provider
  def node_states do
    Application.get_env(:flux, :test_node_states) ||
      [%{node: node(), tier: license_map().tier, license_id: nil, valid_until: nil}]
  end
end
