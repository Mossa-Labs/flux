defmodule Flux.Alerts.RegistryTest do
  # async: false — set_active/1 mutates the global registry ETS table.
  use ExUnit.Case, async: false

  alias Flux.Alerts.Registry

  setup do
    on_exit(fn -> Registry.set_active(Flux.Alerts.Providers.Community) end)
    :ok
  end

  test "set_active/active round-trips the provider module" do
    Registry.set_active(Flux.AlertsTestProvider)
    assert Registry.active() == Flux.AlertsTestProvider

    Registry.set_active(Flux.Alerts.Providers.Community)
    assert Registry.active() == Flux.Alerts.Providers.Community
  end
end
