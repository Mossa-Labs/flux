defmodule FluxWeb.Components.BrandTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias FluxWeb.Components.Brand

  test "renders the tile and the wordmark" do
    html = render_component(&Brand.brand_mark/1, [])

    assert html =~ "FLUX"
    assert html =~ "bg-primary"
  end

  test "uses the primary-content token rather than a literal white" do
    # text-white is indistinguishable from text-primary-content today (the token
    # resolves to #ffffff in both themes), so nothing visual asserts the
    # difference — but it stops being the same the moment the primary colour is
    # customisable, and a pale brand colour would render white-on-white.
    html = render_component(&Brand.brand_mark/1, [])

    assert html =~ "text-primary-content"
    refute html =~ "text-white"
  end

  test "accepts extra wrapper classes" do
    html = render_component(&Brand.brand_mark/1, class: "px-2")
    assert html =~ "px-2"
  end

  describe "the mark is defined in exactly one place" do
    # It previously existed as a byte-identical copy in three layouts, so a
    # change to it meant finding all three. These read the templates as text
    # because the layouts cannot be rendered in isolation.
    @layouts [
      "lib/flux_web/components/layouts.ex",
      "lib/flux_web/components/layouts/dashboard.html.heex",
      "lib/flux_web/components/layouts/builder.html.heex"
    ]

    test "no layout re-implements the tile" do
      for path <- @layouts do
        refute File.read!(path) =~ "rounded-lg bg-primary flex items-center justify-center",
               "#{path} has its own copy of the brand tile — call Brand.brand_mark/1 instead"
      end
    end

    test "every layout renders the shared component" do
      for path <- @layouts do
        assert File.read!(path) =~ "Brand.brand_mark",
               "#{path} no longer renders the shared brand mark"
      end
    end
  end
end
