defmodule Flux.Observability.RegistryTest do
  # async: false — set_active/1 mutates the global registry ETS table.
  use ExUnit.Case, async: false

  alias Flux.Observability.Registry

  setup do
    on_exit(fn -> Registry.set_active(Flux.Observability.Providers.Community) end)
    :ok
  end

  test "set_active/active round-trips the provider module" do
    Registry.set_active(Flux.ObservabilityTestProvider)
    assert Registry.active() == Flux.ObservabilityTestProvider

    Registry.set_active(Flux.Observability.Providers.Community)
    assert Registry.active() == Flux.Observability.Providers.Community
  end
end
