defmodule FluxWeb.BrandingControllerTest do
  # async: false — swaps the global provider registry and the license tier.
  use FluxWeb.ConnCase, async: false

  import Flux.LicenseHelpers

  alias Flux.Branding
  alias Flux.Branding.Theme

  setup do
    # put_license_tier/1 hands back prior state rather than restoring itself.
    prior_license =
      {Application.get_env(:flux, Flux.License), Application.get_env(:flux, :test_license_tier)}

    on_exit(fn ->
      Flux.LicenseHelpers.reset_license(prior_license)
      Branding.Registry.set_active(Flux.Branding.Providers.Community)
      Application.delete_env(:flux, :test_branding_theme)
    end)

    :ok
  end

  defp brand(theme) do
    put_license_tier(:enterprise)
    Application.put_env(:flux, :test_branding_theme, theme)
    Branding.Registry.set_active(Flux.BrandingTestProvider)
    theme
  end

  test "a Community deployment serves an empty, uncacheable stylesheet", %{conn: conn} do
    conn = get(conn, ~p"/branding/theme/whatever")

    assert response(conn, 200) == ""
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "a branded deployment serves its accent colour", %{conn: conn} do
    theme = brand(%Theme{primary_color: "#ff0000", primary_content: "#000000"})

    conn = get(conn, ~p"/branding/theme/#{Theme.color_digest(theme)}")
    css = response(conn, 200)

    assert css =~ "--color-primary: #ff0000"
    assert css =~ "--color-primary-content: #000000"
    assert response_content_type(conn, :css) =~ "text/css"
  end

  test "overrides beat daisyUI's own theme blocks in both themes", %{conn: conn} do
    theme = brand(%Theme{primary_color: "#ff0000"})
    css = conn |> get(~p"/branding/theme/#{Theme.color_digest(theme)}") |> response(200)

    # daisyUI emits at (0,1,0) under both :root and [data-theme=…]; matching that
    # would leave the winner to source order, which we do not control.
    assert css =~ ~s(html[data-theme="dark"])
    assert css =~ ~s(html[data-theme="light"])
  end

  test "the base surfaces are never overridable", %{conn: conn} do
    theme = brand(%Theme{primary_color: "#ff0000"})
    css = conn |> get(~p"/branding/theme/#{Theme.color_digest(theme)}") |> response(200)

    # Handing these over is how an operator makes their own install unreadable.
    refute css =~ "--color-base-100"
    refute css =~ "--color-base-content"
  end

  describe "caching" do
    test "a current digest caches immutably", %{conn: conn} do
      theme = brand(%Theme{primary_color: "#ff0000"})

      conn = get(conn, ~p"/branding/theme/#{Theme.color_digest(theme)}")

      assert get_resp_header(conn, "cache-control") == [
               "public, max-age=31536000, immutable"
             ]
    end

    test "a stale digest still serves current colours, but uncacheable", %{conn: conn} do
      brand(%Theme{primary_color: "#ff0000"})

      # An open tab or a bookmark holding yesterday's URL. Serving a 404 would
      # break its styling; caching it for a year under a digest that no longer
      # describes the content would be worse.
      conn = get(conn, ~p"/branding/theme/staledigest000000")

      assert response(conn, 200) =~ "--color-primary: #ff0000"
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end
  end

  describe "CSS injection" do
    # Deliberately bypasses the write path. The provider validating on save is one
    # control; this proves the controller does not depend on it having worked.
    test "a colour that would close the rule is refused at render", %{conn: conn} do
      brand(%Theme{primary_color: "#fff; } body { background: url(https://evil/) "})

      conn = get(conn, ~p"/branding/theme/anything")
      css = response(conn, 200)

      assert css == ""
      refute css =~ "evil"
    end

    test "a poisoned foreground is refused too", %{conn: conn} do
      brand(%Theme{primary_color: "#ff0000", primary_content: "red; } html { display: none"})

      assert conn |> get(~p"/branding/theme/anything") |> response(200) == ""
    end

    test "the accepted grammar is exactly #rrggbb" do
      assert Theme.valid_color?("#5e6ad2")
      assert Theme.valid_color?("#ABCDEF")

      refute Theme.valid_color?("#fff")
      refute Theme.valid_color?("#5e6ad2ff")
      refute Theme.valid_color?("rgb(1,2,3)")
      refute Theme.valid_color?("red")
      refute Theme.valid_color?("#5e6ad2;")
      refute Theme.valid_color?(nil)
    end
  end
end
