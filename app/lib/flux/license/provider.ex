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
  @typedoc """
  License lifecycle status, derived from `valid_until`:

    * `:active` — comfortably within the paid period
    * `:near_expiry` — expiring soon (renew reminder)
    * `:grace` — past `valid_until` but inside the grace window (still entitled)
    * `:expired` — past the grace window

  Informational only — providers report it for UI banners. Enforcing a
  downgrade on `:expired` is a separate concern.
  """
  @type status :: :active | :near_expiry | :grace | :expired
  @type license :: %{
          optional(:tier) => tier(),
          optional(:features) => [feature()],
          optional(:org) => String.t() | nil,
          optional(:valid_until) => DateTime.t() | nil,
          optional(:node_count) => pos_integer() | nil,
          optional(:status) => status(),
          optional(:grace_until) => DateTime.t() | nil,
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

  @doc """
  Optional: apply a signed license token (verify + persist), returning the
  resolved license. Providers that can activate a license at runtime (the
  commercial edition) implement this; the Community stub does not, so
  `Flux.License.apply_license/1` reports `{:error, :unsupported}` and the
  activation UI stays hidden.
  """
  @callback apply_license(token :: String.t()) :: {:ok, license()} | {:error, term()}

  @optional_callbacks entitled?: 1, apply_license: 1
end
