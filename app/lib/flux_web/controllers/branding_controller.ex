defmodule FluxWeb.BrandingController do
  @moduledoc """
  Serves branding assets: the accent-colour stylesheet, and (later) the logo and
  favicon (MOS-483).

  Unauthenticated by necessity — the sign-in page is branded, and a visitor there
  has no session. That is acceptable because branding is public by definition:
  it is what the product looks like to anyone who can reach it.

  URLs are **content-addressed**. The digest in the path means a change produces
  a new URL, which lets every response be cached immutably and removes any need
  to revalidate.
  """
  use FluxWeb, :controller

  alias Flux.Branding.Theme

  @doc """
  The custom logo.

  Every header here is doing a job, and the first two are the ones that matter:

    * **`content-type`** comes from the provider's verdict on the bytes, never
      from anything an uploader declared. Serving attacker bytes under a
      scriptable type is the whole risk this endpoint carries.
    * **`x-content-type-options: nosniff`** stops a browser second-guessing that
      type. Without it a PNG that is really HTML can still be executed. Set here
      *and* by the pipeline's `put_secure_browser_headers` — deliberately
      redundant, because this response must carry it even if a future change
      trims that pipeline for being asset-only. Neither line is dead; removing
      just one leaves the header in place, which is the point.
    * **`content-disposition`** names the file ourselves. The uploaded name is
      never stored, let alone echoed — CR/LF and quotes in that header are their
      own injection class, and we have no use for the original name.
    * **`content-security-policy: default-src 'none'; sandbox`** is belt and
      braces: even if something got through and a browser were talked into
      treating it as a document, it can do nothing.
  """
  def logo(conn, params), do: serve_asset(conn, :logo, params)

  @doc """
  The custom favicon. Identical handling to the logo — see above.
  """
  def favicon(conn, params), do: serve_asset(conn, :favicon, params)

  defp serve_asset(conn, kind, %{"digest" => requested}) do
    case Flux.Branding.asset(deployment_org_id(), kind) do
      {:ok, bytes, content_type, digest} ->
        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_header("content-disposition", ~s(inline; filename="#{kind}.png"))
        |> put_resp_header("content-security-policy", "default-src 'none'; sandbox")
        |> put_resp_header("etag", ~s("#{digest}"))
        |> put_cache_headers(requested == digest)
        |> send_resp(200, bytes)

      :none ->
        # No logo, or entitlement lapsed since the page was rendered. A 404 is
        # right here rather than a stock image: the markup only asks for this
        # URL when a logo exists, so this is genuinely "gone", and a placeholder
        # would be cached in its place.
        conn
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(404, "")
    end
  end

  @doc """
  The accent-colour override.

  Rebuilt from the caller's current theme rather than from the digest — the
  digest identifies the content, it is not a key to look anything up by. A stale
  digest (an open tab, a bookmarked URL) therefore gets the *current* colours
  rather than a 404, and is told not to cache them.
  """
  def theme(conn, %{"digest" => requested}) do
    # Resolved from the deployment, not from a session. This route deliberately
    # skips the :browser pipeline — brandng an asset request with a session fetch
    # and a user-token DB lookup would put a query on every page load, and the
    # sign-in page has no session anyway.
    #
    # It follows that on a multi-org install every visitor gets the deployment
    # organization's colours. That is the same single-org assumption documented
    # on Flux.Branding, applied consistently rather than half-honoured.
    theme = Flux.Branding.for_deployment()

    if Theme.custom_color?(theme) and emittable?(theme) do
      current = Theme.color_digest(theme)

      conn
      |> put_resp_content_type("text/css")
      |> put_cache_headers(requested == current)
      |> send_resp(200, css(theme))
    else
      # Entitlement lapsed, or branding was cleared, since the page was rendered.
      # An empty stylesheet is the honest answer: nothing to override.
      conn
      |> put_resp_content_type("text/css")
      |> put_resp_header("cache-control", "no-store")
      |> send_resp(200, "")
    end
  end

  # Same reasoning as the stylesheet: this route skips the :browser pipeline, so
  # there is no session to resolve an organization from, and the deployment's is
  # the answer consistent with the documented single-org assumption.
  defp deployment_org_id, do: Flux.Branding.provider().deployment_org_id()

  # Re-validated here, at the point of output, and not only where it was written.
  # A hand-edited row, a bad migration or some future bulk-import path must not be
  # able to reach `css/1` with a value that closes the rule and opens another. The
  # provider validating on write is the first line; this is the one that is
  # actually adjacent to the injection sink.
  defp emittable?(%Theme{primary_color: color, primary_content: content}) do
    Theme.valid_color?(color) and Theme.valid_color?(content)
  end

  # Only when the URL matches what we would generate now. A stale URL must not be
  # cached for a year under a digest that no longer describes its contents.
  defp put_cache_headers(conn, true),
    do: put_resp_header(conn, "cache-control", "public, max-age=31536000, immutable")

  defp put_cache_headers(conn, false),
    do: put_resp_header(conn, "cache-control", "no-store")

  # Overrides daisyUI's theme variables rather than introducing a new data-theme
  # value, which would fight the dark-mode custom variant.
  #
  # The selector list is not decoration: daisyUI emits its blocks at specificity
  # (0,1,0) under both `:root` and `[data-theme=…]`. Matching that would leave the
  # winner down to source order, which we do not control. `html[data-theme="…"]`
  # is (0,1,1) and wins outright in either theme.
  #
  # Only the accent trio is overridden. The base surfaces are deliberately NOT
  # customisable: they carry the contrast the whole interface is built on, so a
  # single unlucky value there makes text unreadable everywhere at once, with no
  # obvious way back. An accent colour can only ever be locally wrong.
  defp css(%Theme{} = theme) do
    color = theme.primary_color
    content = theme.primary_content

    """
    html,
    html[data-theme="dark"],
    html[data-theme="light"] {
      --color-primary: #{color};
      --color-primary-content: #{content};
      --color-secondary: #{color};
      --color-secondary-content: #{content};
      --color-accent: #{color};
      --color-accent-content: #{content};
      --color-lavender: #{color};
    }
    """
  end
end
