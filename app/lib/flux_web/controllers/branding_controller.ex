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
