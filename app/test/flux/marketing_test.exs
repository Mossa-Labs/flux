defmodule Flux.MarketingTest do
  use ExUnit.Case, async: true

  describe "pricing_url/0" do
    test "ends in .html" do
      # The site is a flat static bundle with no extensionless rewrite: dropping
      # the suffix turns every Upgrade CTA in the product into a 404 (MOS-607).
      assert String.ends_with?(Flux.Marketing.pricing_url(), ".html")
    end

    test "lives on the marketing site" do
      assert String.starts_with?(Flux.Marketing.pricing_url(), Flux.Marketing.site_url() <> "/")
    end
  end

  describe "site_url/0" do
    test "is an https origin with no trailing slash" do
      url = Flux.Marketing.site_url()

      assert String.starts_with?(url, "https://")
      refute String.ends_with?(url, "/")
    end
  end
end
