defmodule Flux.License.Provider do
  @moduledoc """
  Contract for license providers.

  Community ships `Flux.License.Providers.Community` (always `:community`
  tier, never entitled to Pro/EE features). EE ships a signed-key or
  online-validator provider that reports `:pro` / `:enterprise` tiers
  with feature entitlements derived from the license payload.
  """

  @type tier :: :community | :pro | :enterprise
  @type feature :: atom()
  @type license :: %{
          optional(:tier) => tier(),
          optional(:features) => [feature()],
          optional(:org) => String.t() | nil,
          optional(:valid_until) => DateTime.t() | nil,
          optional(:node_count) => pos_integer() | nil,
          optional(atom()) => any()
        }

  @callback fetch() :: {:ok, license()} | {:error, term()}

  @callback tier() :: tier()

  @doc """
  Optional per-feature override. When a provider does not implement this,
  `Flux.License` derives entitlement from `tier/0` against
  `Flux.License.Features`. Providers should prefer reporting an accurate
  `tier/0` rather than overriding this.
  """
  @callback entitled?(feature()) :: boolean()

  @optional_callbacks entitled?: 1
end
