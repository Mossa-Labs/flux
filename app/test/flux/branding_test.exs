defmodule Flux.BrandingTest do
  # async: false — swaps the global provider registry and the license tier.
  use ExUnit.Case, async: false

  import Flux.LicenseHelpers

  alias Flux.Branding
  alias Flux.Branding.Theme

  setup do
    # put_license_tier/1 hands back prior state rather than restoring itself, so
    # without this the tier leaks into every later test in the run.
    prior_license =
      {Application.get_env(:flux, Flux.License), Application.get_env(:flux, :test_license_tier)}

    on_exit(fn ->
      Flux.LicenseHelpers.reset_license(prior_license)
      Branding.Registry.set_active(Flux.Branding.Providers.Community)
      Application.delete_env(:flux, :test_branding_theme)
      Application.delete_env(:flux, :test_branding_put_result)
      Application.delete_env(:flux, :test_branding_org_id)
    end)

    :ok
  end

  defp use_test_provider(theme) do
    Application.put_env(:flux, :test_branding_theme, theme)
    Branding.Registry.set_active(Flux.BrandingTestProvider)
  end

  describe "a Community build" do
    test "reports stock branding for any organization" do
      assert Branding.for_org(1) == Theme.default()
      assert Branding.for_deployment() == Theme.default()
    end

    test "refuses writes" do
      assert {:error, [{:base, msg}]} = Branding.put(1, %{"brand_name" => "Acme"})
      assert msg =~ "Enterprise"
    end

    test "stock branding needs no colour override served" do
      refute Theme.custom_color?(Theme.default())
      assert Theme.color_digest(Theme.default()) == nil
    end
  end

  describe "an entitled build" do
    setup do
      put_license_tier(:enterprise)
      :ok
    end

    test "reports the provider's theme" do
      use_test_provider(%Theme{brand_name: "Acme", primary_color: "#ff0000"})

      assert %Theme{brand_name: "Acme"} = Branding.for_org(1)
    end

    test "falls back to the deployment organization when a scope has none" do
      use_test_provider(%Theme{brand_name: "Acme"})
      Application.put_env(:flux, :test_branding_org_id, 7)

      assert %Theme{brand_name: "Acme"} = Branding.for_scope(%{organization_id: nil})
      assert %Theme{brand_name: "Acme"} = Branding.for_scope(nil)
    end

    test "uses the scope's own organization when it has one" do
      use_test_provider(%Theme{brand_name: "Acme"})

      assert %Theme{brand_name: "Acme"} = Branding.for_scope(%{organization_id: 3})
    end
  end

  describe "entitlement lapsing" do
    test "reverts to stock immediately, without a restart" do
      # The provider keeps reporting Acme; the facade must stop believing it the
      # moment the tier drops. A customer who stops paying for white-label should
      # stop seeing it, not keep their branding until someone bounces the node.
      put_license_tier(:enterprise)
      use_test_provider(%Theme{brand_name: "Acme", primary_color: "#ff0000"})
      assert %Theme{brand_name: "Acme"} = Branding.for_org(1)

      put_license_tier(:community)

      assert Branding.for_org(1) == Theme.default()
      assert Branding.for_deployment() == Theme.default()
      assert {:error, _} = Branding.put(1, %{"brand_name" => "Acme"})
    end
  end

  describe "colour digests" do
    test "change when either the accent or its foreground changes" do
      a = %Theme{primary_color: "#ff0000", primary_content: "#ffffff"}
      b = %Theme{primary_color: "#00ff00", primary_content: "#ffffff"}
      # Same accent, different foreground — a recontrast must still bust the URL,
      # or a cached stylesheet keeps serving unreadable text forever.
      c = %Theme{primary_color: "#ff0000", primary_content: "#000000"}

      assert Theme.color_digest(a) != Theme.color_digest(b)
      assert Theme.color_digest(a) != Theme.color_digest(c)
      assert Theme.color_digest(a) == Theme.color_digest(%Theme{a | brand_name: "Other"})
    end

    test "a customer who picks the stock colour needs no override" do
      refute Theme.custom_color?(%Theme{primary_color: Theme.stock_primary()})
    end
  end
end
