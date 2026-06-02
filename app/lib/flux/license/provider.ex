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
          optional(:valid_until) => DateTime.t() | nil,
          optional(atom()) => any()
        }

  @callback fetch() :: {:ok, license()} | {:error, term()}

  @callback entitled?(feature()) :: boolean()

  @callback tier() :: tier()
end
