defmodule FluxWeb.Components.BuildFooterTest do
  use FluxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Flux.BuildInfo

  describe "build_footer/1" do
    test "renders the build identity" do
      html = render_component(&FluxWeb.Layouts.build_footer/1, %{})

      assert html =~ BuildInfo.short()
    end

    test "flags a build that did not come from the release pipeline" do
      # The test build carries no injected revision, so the warning must show —
      # the whole point is that an unreproducible build is not mistaken for a
      # shipped one.
      refute BuildInfo.released?()

      assert render_component(&FluxWeb.Layouts.build_footer/1, %{}) =~ "dev build"
    end
  end

  describe "every page" do
    test "carries the footer, so support can read the build off any screen", %{conn: conn} do
      # The login page: reachable before authenticating, which is where a
      # confused operator is most likely to be standing.
      html = conn |> get(~p"/users/log-in") |> html_response(200)

      assert html =~ "<footer"
      assert html =~ BuildInfo.short()
    end
  end
end
