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
  @typedoc """
  How many nodes are running against how many the license covers.

  `:live` and `:licensed` are counts; `:over?` is the provider's verdict, not a
  comparison for the caller to redo. Reporting the verdict rather than letting
  each reader compare the two counts is deliberate: what counts as a node, and
  what to do about `nil`, are the provider's business, and a second comparison
  elsewhere is a second definition waiting to disagree with the first.
  """
  @type capacity :: %{live: pos_integer(), licensed: pos_integer(), over?: boolean()}
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

  @doc """
  Optional: what each node in the cluster currently has loaded.

  On a multi-node deployment, applying a license is only meaningful cluster-wide —
  a confirmation from whichever node served the request says nothing about the
  others. Providers that support clustering report per-node state so the UI can
  show that a renewal actually landed everywhere; single-node providers omit it
  and `Flux.License.node_states/0` reports just this node.

  Each entry carries at least `:node` and `:tier`. A node that could not be
  reached is reported with tier `:unreachable` rather than dropped — during a
  rolling restart, "we could not ask" and "it is not licensed" mean very
  different things.
  """
  @callback node_states() :: [map()]

  @doc """
  Optional: how many nodes are running against how many the license covers, or
  `nil` when this edition has no node cap to report.

  Editions that are single-node by construction have nothing to say here and
  omit the callback; `Flux.License.node_capacity/0` then reports `nil` and the
  UI stays silent. A provider that *does* cap nodes also returns `nil` when a
  particular license is uncapped, so "unlimited" and "not applicable" render
  identically rather than needing a sentinel the UI has to know about.

  Whether the deployment is over its cap is the provider's verdict — see
  `t:capacity/0`. Callers render it; they do not recompute it.
  """
  @callback node_capacity() :: capacity() | nil

  @optional_callbacks entitled?: 1, apply_license: 1, node_states: 0, node_capacity: 0
end
