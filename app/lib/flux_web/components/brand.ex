defmodule FluxWeb.Components.Brand do
  @moduledoc """
  The Flux brand mark — the accent tile plus the wordmark.

  Rendered in the app header, the dashboard sidebar and the pipeline-builder
  navbar. Those three carried a byte-identical copy of the markup, so a change to
  the mark meant finding all three; this is the single home for it.

  Each caller keeps its own wrapper (an `<a>`, a `<div>`, a `<.link>`) because
  they genuinely differ — only the mark itself is shared.
  """
  use Phoenix.Component

  attr :class, :string, default: nil, doc: "extra classes for the wrapper"

  @doc """
  Renders the brand mark.
  """
  def brand_mark(assigns) do
    ~H"""
    <div class={["flex items-center gap-3", @class]}>
      <%!--
      text-primary-content, not text-white: it is the daisyUI token for "readable
      on primary", and it already resolves to #ffffff in both themes, so this is
      identical today. It stops being identical once the primary colour is
      customisable, which is the point.
      --%>
      <div class="w-8 h-8 rounded-lg bg-primary flex items-center justify-center text-primary-content font-bold">
        F
      </div>
      <span class="text-2xl font-black tracking-tighter text-base-content">FLUX</span>
    </div>
    """
  end
end
