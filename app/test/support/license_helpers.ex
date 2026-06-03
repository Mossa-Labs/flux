defmodule Flux.LicenseHelpers do
  @moduledoc """
  Helpers for exercising license-gated behaviour in tests.

  These swap the globally-configured license provider via `Application.put_env`,
  so any test using them MUST be `async: false`. `with_license_tier/2` restores
  the previous provider afterwards.
  """

  @doc """
  Runs `fun` with the license reporting `tier`, restoring the previous provider
  afterwards (even if `fun` raises).
  """
  @spec with_license_tier(Flux.License.Provider.tier(), (-> result)) :: result when result: any()
  def with_license_tier(tier, fun) when is_function(fun, 0) do
    state = put_license_tier(tier)

    try do
      fun.()
    after
      reset_license(state)
    end
  end

  @doc """
  Swaps in the test provider at `tier` and returns the prior state. Pair with
  `reset_license/1` (e.g. via `on_exit/1`) when you can't wrap in a closure.
  """
  @spec put_license_tier(Flux.License.Provider.tier()) :: {term(), term()}
  def put_license_tier(tier) do
    prior =
      {Application.get_env(:flux, Flux.License), Application.get_env(:flux, :test_license_tier)}

    Application.put_env(:flux, Flux.License, provider: Flux.LicenseTestProvider)
    Application.put_env(:flux, :test_license_tier, tier)
    prior
  end

  @doc "Restores the provider state captured by `put_license_tier/1`."
  @spec reset_license({term(), term()}) :: :ok
  def reset_license({prior_provider, prior_tier}) do
    restore(:flux, Flux.License, prior_provider)
    restore(:flux, :test_license_tier, prior_tier)
    :ok
  end

  defp restore(app, key, nil), do: Application.delete_env(app, key)
  defp restore(app, key, value), do: Application.put_env(app, key, value)
end
