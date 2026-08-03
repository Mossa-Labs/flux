defmodule Flux.BrandingTestProvider do
  @moduledoc """
  Branding provider stand-in for the commercial edition. Drive it via
  `Application` env:

    * `:test_branding_theme` — the `Flux.Branding.Theme` returned by `theme/1`
      (default: stock).
    * `:test_branding_put_result` — what `put/2` returns (default: `{:ok, theme}`).
    * `:test_branding_org_id` — what `deployment_org_id/0` reports.

  The theme is supplied **whole**, already resolved. That is the point: the
  public repo derives nothing about branding, so a test that set raw fields and
  expected the UI to work them out would be asserting the wrong thing — it would
  pass just as happily against a layout that had reinvented the logic locally.

  Tests using it MUST be `async: false` (it swaps a global registry entry).
  """

  @behaviour Flux.Branding.Provider

  alias Flux.Branding.Theme

  @impl Flux.Branding.Provider
  def theme(_org_id), do: Application.get_env(:flux, :test_branding_theme, Theme.default())

  @impl Flux.Branding.Provider
  def put(_org_id, _attrs),
    do: Application.get_env(:flux, :test_branding_put_result, {:ok, theme(nil)})

  @impl Flux.Branding.Provider
  def deployment_org_id, do: Application.get_env(:flux, :test_branding_org_id)

  @doc """
  `:test_branding_asset` drives this as `{bytes, content_type, digest}`.

  Supplying the content type here rather than deriving it is the point: the
  public side must serve whatever the provider concluded the bytes are, so a
  test can hand it a mismatch — HTML bytes labelled `image/png` — and assert the
  header still comes from the provider.
  """
  @impl Flux.Branding.Provider
  def asset(_org_id, kind) do
    case Application.get_env(:flux, :test_branding_asset) do
      {bytes, type, digest} when kind == :logo -> {:ok, bytes, type, digest}
      _ -> :none
    end
  end

  @impl Flux.Branding.Provider
  def put_asset(_org_id, _kind, _bytes),
    do: Application.get_env(:flux, :test_branding_put_asset_result, {:ok, theme(nil)})
end
