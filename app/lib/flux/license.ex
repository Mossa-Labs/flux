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

  @doc """
  The current license lifecycle status (`:active | :near_expiry | :grace |
  :expired`) reported by the provider, defaulting to `:active` when the provider
  does not supply one.
  """
  @spec status() :: Flux.License.Provider.status()
  def status do
    case fetch() do
      {:ok, license} -> Map.get(license, :status, :active)
      {:error, _} -> :active
    end
  end

  @doc """
  Whether the configured provider supports applying a license at runtime. The
  Community stub does not, so the activation UI is only offered when an
  activation-capable provider (the commercial edition) is configured.
  """
  @spec activation_supported?() :: boolean()
  def activation_supported?, do: supports_apply?(provider())

  @doc """
  Applies a signed license token via the configured provider (verify + persist),
  returning the resolved license. Returns `{:error, :unsupported}` when the
  provider can't activate licenses (e.g. the Community build).
  """
  @spec apply_license(String.t()) ::
          {:ok, Flux.License.Provider.license()} | {:error, term()}
  def apply_license(token) when is_binary(token) do
    mod = provider()

    if supports_apply?(mod) do
      mod.apply_license(token)
    else
      {:error, :unsupported}
    end
  end

  @doc """
  What each node in the cluster currently has loaded.

  Applying a license on a multi-node deployment is only meaningful cluster-wide:
  a success message from whichever node served the request says nothing about the
  others. Providers that cluster report per-node state; otherwise this reports
  just the local node, which is the honest answer for a single-node build.
  """
  @spec node_states() :: [map()]
  def node_states do
    mod = provider()

    if Code.ensure_loaded?(mod) and function_exported?(mod, :node_states, 0) do
      mod.node_states()
    else
      [%{node: node(), tier: tier(), license_id: nil, valid_until: nil}]
    end
  end

  @doc """
  How many nodes are running against how many the license covers, or `nil` when
  there is no cap to report.

  `nil` is the answer for a build that is single-node by construction, and also
  for an uncapped license — so "not applicable" and "unlimited" look the same to
  a caller, which is what they want, because neither is something to warn about.

  The provider decides what counts as a node and whether the deployment is over
  its cap; this returns that verdict verbatim. Do not re-derive `over?` by
  comparing the counts — see `t:Flux.License.Provider.capacity/0`.
  """
  @spec node_capacity() :: Flux.License.Provider.capacity() | nil
  def node_capacity do
    mod = provider()

    if Code.ensure_loaded?(mod) and function_exported?(mod, :node_capacity, 0) do
      mod.node_capacity()
    end
  end

  # `function_exported?/3` does not auto-load the module, so ensure it's loaded
  # before checking (the provider is referenced only as an atom in config).
  defp supports_apply?(mod),
    do: Code.ensure_loaded?(mod) and function_exported?(mod, :apply_license, 1)
end
