defmodule FluxWeb.Components.Brand do
  @moduledoc """
  The brand mark — the accent tile plus the wordmark.

  Rendered in the app header, the dashboard sidebar and the pipeline-builder
  navbar. Those three carried a byte-identical copy of the markup, so a change to
  the mark meant finding all three; this is the single home for it.

  Each caller keeps its own wrapper (an `<a>`, a `<div>`, a `<.link>`) because
  they genuinely differ — only the mark itself is shared.
  """
  use Phoenix.Component
  use FluxWeb, :verified_routes

  alias Flux.Branding.Theme

  attr :branding, :any,
    default: nil,
    doc: "a Flux.Branding.Theme; falls back to stock when absent"

  attr :class, :string, default: nil, doc: "extra classes for the wrapper"

  @doc """
  Renders the brand mark.
  """
  def brand_mark(assigns) do
    assigns = assign_new(assigns, :theme, fn -> assigns[:branding] || Theme.default() end)

    ~H"""
    <div class={["flex items-center gap-3", @class]}>
      <%!--
      A custom logo replaces the tile rather than sitting beside it. The alt text
      is the brand name, so a screen reader hears the same thing either way, and
      the wordmark stays: a logo is usually a mark, not a full lockup.

      Content-addressed URL, so this is cached immutably and a new upload is a
      new URL rather than a stale image nobody can flush.
      --%>
      <img
        :if={@theme.logo_digest}
        src={~p"/branding/logo/#{@theme.logo_digest}"}
        alt={@theme.brand_name}
        class="w-8 h-8 rounded-lg object-contain"
      />
      <%!--
      text-primary-content, not text-white: it is the daisyUI token for "readable
      on primary", and the colour override ships a matching value, so a pale
      brand colour gets dark text instead of white-on-white.
      --%>
      <div
        :if={!@theme.logo_digest}
        class="w-8 h-8 rounded-lg bg-primary flex items-center justify-center text-primary-content font-bold overflow-hidden"
      >
        {initial(@theme.brand_name)}
      </div>
      <span class="text-2xl font-black tracking-tighter text-base-content">
        {@theme.brand_name}
      </span>
    </div>
    """
  end

  # The tile shows one glyph. Taking the first grapheme rather than the first
  # byte keeps multi-byte names (accents, non-Latin scripts) from rendering as
  # a broken character.
  defp initial(name) do
    name
    |> String.trim()
    |> String.first()
    |> case do
      nil -> "F"
      c -> String.upcase(c)
    end
  end
end
