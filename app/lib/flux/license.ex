defmodule Flux.License do
  @moduledoc """
  Facade over the configured `Flux.License.Provider`.

  The provider module is configured via `config :flux, Flux.License,
  provider: Flux.License.Providers.Community`. EE builds switch to the
  EE provider via the commercial edition's runtime config.

  ## Pro/EE feature atoms

  The canonical tier→feature catalog lives in `Flux.License.Features`.
  Providers only report a `tier/0`; entitlement is derived from that tier
  against the catalog. Use `has_feature?/1` (or its alias `entitled?/1`) for
  consistent checks across the codebase.
  """

  alias Flux.License.Features

  @spec provider() :: module()
  def provider do
    case Application.get_env(:flux, __MODULE__) do
      nil ->
        raise "No license provider configured. Set config :flux, Flux.License, provider: Flux.License.Providers.Community"

      config ->
        Keyword.fetch!(config, :provider)
    end
  end

  @spec fetch() :: {:ok, Flux.License.Provider.license()} | {:error, term()}
  def fetch, do: provider().fetch()

  @doc """
  Returns `true` when the current license tier entitles `feature`.

  If the configured provider exports an `entitled?/1` override it is used;
  otherwise entitlement is derived from `tier/0` against
  `Flux.License.Features`.
  """
  @spec has_feature?(Flux.License.Provider.feature()) :: boolean()
  def has_feature?(feature) when is_atom(feature) do
    mod = provider()

    if function_exported?(mod, :entitled?, 1) do
      mod.entitled?(feature)
    else
      feature in Features.for_tier(tier())
    end
  end

  @doc "Alias for `has_feature?/1`, kept for existing call sites."
  @spec entitled?(Flux.License.Provider.feature()) :: boolean()
  def entitled?(feature) when is_atom(feature), do: has_feature?(feature)

  @spec tier() :: Flux.License.Provider.tier()
  def tier, do: provider().tier()
end
