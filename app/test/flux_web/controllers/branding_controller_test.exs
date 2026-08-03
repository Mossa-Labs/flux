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

  describe "the logo endpoint" do
    setup do
      on_exit(fn -> Application.delete_env(:flux, :test_branding_asset) end)
    end

    defp serve_logo(bytes, type \\ "image/png", digest \\ "abc123") do
      brand(%Theme{logo_digest: digest})
      Application.put_env(:flux, :test_branding_asset, %{logo: {bytes, type, digest}})
      digest
    end

    test "serves the bytes with the provider's content type", %{conn: conn} do
      digest = serve_logo("PNGBYTES")

      conn = get(conn, ~p"/branding/logo/#{digest}")

      assert response(conn, 200) == "PNGBYTES"
      assert get_resp_header(conn, "content-type") == ["image/png; charset=utf-8"]
    end

    test "the content type comes from the provider, never from the stored bytes", %{conn: conn} do
      # The whole risk this endpoint carries is serving attacker bytes under a
      # scriptable type. Even if something HTML-shaped reached storage, the type
      # is the provider's verdict and nosniff stops the browser second-guessing.
      digest = serve_logo("<html><script>alert(1)</script></html>")

      conn = get(conn, ~p"/branding/logo/#{digest}")

      assert get_resp_header(conn, "content-type") == ["image/png; charset=utf-8"]
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
      assert get_resp_header(conn, "content-security-policy") == ["default-src 'none'; sandbox"]
    end

    test "names the file itself rather than echoing an upload", %{conn: conn} do
      # The uploaded filename is never stored. Echoing one into this header is
      # its own injection class (CR/LF, quotes) and buys nothing.
      digest = serve_logo("PNGBYTES")

      conn = get(conn, ~p"/branding/logo/#{digest}")

      assert get_resp_header(conn, "content-disposition") == [~s(inline; filename="logo.png")]
    end

    test "a current digest caches immutably and carries an ETag", %{conn: conn} do
      digest = serve_logo("PNGBYTES")

      conn = get(conn, ~p"/branding/logo/#{digest}")

      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
      assert get_resp_header(conn, "etag") == [~s("#{digest}")]
    end

    test "a stale digest serves current bytes but is not cached", %{conn: conn} do
      serve_logo("PNGBYTES")

      conn = get(conn, ~p"/branding/logo/oldstaledigest")

      assert response(conn, 200) == "PNGBYTES"
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    test "404s when there is no logo, without caching the absence", %{conn: conn} do
      brand(%Theme{})

      conn = get(conn, ~p"/branding/logo/anything")

      assert response(conn, 404) == ""
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    test "a Community deployment has no logo to serve", %{conn: conn} do
      conn = get(conn, ~p"/branding/logo/anything")
      assert response(conn, 404) == ""
    end
  end

  describe "the favicon endpoint" do
    setup do
      on_exit(fn -> Application.delete_env(:flux, :test_branding_asset) end)
    end

    test "serves the favicon with the same protections as the logo", %{conn: conn} do
      brand(%Theme{favicon_digest: "fav123"})

      Application.put_env(:flux, :test_branding_asset, %{
        favicon: {"ICONBYTES", "image/png", "fav123"}
      })

      conn = get(conn, ~p"/branding/favicon/fav123")

      assert response(conn, 200) == "ICONBYTES"
      assert get_resp_header(conn, "content-type") == ["image/png; charset=utf-8"]
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
      assert get_resp_header(conn, "content-security-policy") == ["default-src 'none'; sandbox"]
      assert get_resp_header(conn, "content-disposition") == [~s(inline; filename="favicon.png")]
    end

    test "404s when none is set", %{conn: conn} do
      brand(%Theme{})
      assert conn |> get(~p"/branding/favicon/anything") |> response(404) == ""
    end

    test "a logo is never served as the favicon", %{conn: conn} do
      # The asset cache was originally keyed by organization alone, which would
      # have answered a favicon miss with the logo. Keyed by {org, kind} now.
      brand(%Theme{logo_digest: "logo123"})

      Application.put_env(:flux, :test_branding_asset, %{
        logo: {"LOGOBYTES", "image/png", "logo123"}
      })

      assert conn |> get(~p"/branding/logo/logo123") |> response(200) == "LOGOBYTES"
      assert conn |> get(~p"/branding/favicon/logo123") |> response(404) == ""
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
