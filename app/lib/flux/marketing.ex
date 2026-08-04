defmodule Flux.Marketing do
  @moduledoc """
  Canonical outward-facing URLs for the Flux website.

  ## Page paths must carry `.html`

  The site is a flat bundle of static files mirrored into object storage — no
  application server, no rewrite rule. A path resolves only if an object of
  exactly that name exists, so `/pricing` is a **404**, not a redirect to
  `/pricing.html`. Every link Flux emits has to spell the extension out.

  That is easy to forget and invisible until a user clicks an Upgrade button
  and lands on an error page, which is why the URLs live here instead of being
  retyped at each call site. Callers that need to point somewhere else — a
  self-hosted billing portal, say — override at the call site rather than
  editing these values.
  """

  @site_url "https://fluxdata.tech"
  @pricing_url "#{@site_url}/pricing.html"

  @doc "The marketing site's home page."
  @spec site_url() :: String.t()
  def site_url, do: @site_url

  @doc "The pricing page backing every upgrade CTA."
  @spec pricing_url() :: String.t()
  def pricing_url, do: @pricing_url
end
