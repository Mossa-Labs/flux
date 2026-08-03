defmodule Flux.Branding.Theme do
  @moduledoc """
  A resolved set of branding values, ready to render.

  This is the contract between the branding provider and everything that draws
  chrome. Anything requiring a *decision* is settled by the provider before the
  struct exists — in particular `:primary_content` arrives already chosen, so no
  layout ever works out what is readable on the accent colour and two call sites
  cannot reach different answers.

  Assets are identified by **digest, not URL**. Building a URL is a routing
  concern and routing lives in the web layer; a provider should not have to know
  the path scheme, and the digest is what makes an asset URL content-addressed
  and therefore safe to cache forever.

  `default/0` is stock Flux — what an unlicensed or unbranded deployment gets.
  """

  @stock_brand_name "FLUX"
  @stock_primary "#5e6ad2"
  @stock_primary_content "#ffffff"

  @type t :: %__MODULE__{
          brand_name: String.t(),
          primary_color: String.t() | nil,
          primary_content: String.t(),
          login_message: String.t() | nil,
          logo_digest: String.t() | nil,
          favicon_digest: String.t() | nil
        }

  defstruct brand_name: @stock_brand_name,
            # nil means "emit no colour override" — the stock accent is already
            # in the compiled stylesheet, so a default deployment ships no extra
            # <link> and makes no extra request.
            primary_color: nil,
            primary_content: @stock_primary_content,
            login_message: nil,
            logo_digest: nil,
            favicon_digest: nil

  @doc "The stock Flux branding. What Community and unbranded deployments render."
  @spec default() :: t()
  def default, do: %__MODULE__{}

  @doc "The accent colour compiled into the stylesheet."
  @spec stock_primary() :: String.t()
  def stock_primary, do: @stock_primary

  @hex ~r/\A#[0-9a-fA-F]{6}\z/

  @doc """
  Whether a string is a colour we are willing to emit into a stylesheet.

  Exactly `#rrggbb`. Three-digit shorthand, eight-digit alpha, `rgb()` and named
  colours are all rejected — not because they are invalid CSS, but because the
  narrowest grammar that expresses a brand colour is the one least able to carry
  anything else.

  **This is a security control, not a formatting nicety.** The value is
  interpolated into a CSS declaration, so anything containing `;` or `}` could
  close the rule and open another. Escaping inside a `<style>` context handles
  `<` and `&` and does nothing about either of those, which is why the check is
  a whitelist rather than an escape.
  """
  @spec valid_color?(term()) :: boolean()
  def valid_color?(value) when is_binary(value), do: Regex.match?(@hex, value)
  def valid_color?(_), do: false

  @doc """
  Whether a colour override needs serving to the browser.

  False for stock and for a customer who happens to have picked the stock colour
  — in both cases the compiled stylesheet is already correct.
  """
  @spec custom_color?(t()) :: boolean()
  def custom_color?(%__MODULE__{primary_color: nil}), do: false
  def custom_color?(%__MODULE__{primary_color: c}), do: c != @stock_primary

  @doc """
  A short, stable identifier for this theme's colour pair, used to make the
  stylesheet URL content-addressed.

  Covers the foreground as well as the accent, so a contrast recalculation
  produces a new URL rather than serving a stale cached stylesheet forever.
  """
  @spec color_digest(t()) :: String.t() | nil
  def color_digest(%__MODULE__{primary_color: nil}), do: nil

  def color_digest(%__MODULE__{primary_color: color, primary_content: content}) do
    :crypto.hash(:sha256, [color, "|", content])
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end
end
