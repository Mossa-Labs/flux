defmodule FluxWeb.SystemSettingsLive.Components do
  @moduledoc """
  Shared building blocks for the System Settings tabs: the tab table and tab bar,
  the card every section sits in, and the empty state for organization-scoped
  tabs.
  """
  use FluxWeb, :html

  # {id, URL slug, label, icon}, in display order. The slug is what appears in
  # ?tab=, so it is part of the page's public surface: bookmarks and links in
  # docs depend on it.
  @tabs [
    {:general, "general", "General", "hero-adjustments-horizontal"},
    {:members, "members", "Members & teams", "hero-users"},
    {:api_keys, "api-keys", "API keys", "hero-key"},
    {:security, "security", "Security", "hero-shield-check"},
    {:branding, "branding", "Branding", "hero-paint-brush"}
  ]

  @doc "The tabs in display order, as `{id, slug, label, icon}`."
  def tabs, do: @tabs

  @doc """
  Resolves the `tab` query param to a tab id.

  A fixed lookup rather than `String.to_atom/1`, so a hand-edited URL can never
  mint an atom. Unknown or missing values fall back to `:general`.
  """
  def tab_from_params(%{"tab" => slug}) do
    Enum.find_value(@tabs, :general, fn {id, s, _label, _icon} -> s == slug && id end)
  end

  def tab_from_params(_params), do: :general

  @doc "The human label for a tab id."
  def tab_label(tab) do
    Enum.find_value(@tabs, fn {id, _slug, label, _icon} -> id == tab && label end)
  end

  @doc """
  The URL for a tab. General is the page's canonical address, so it carries no
  query string.
  """
  def tab_path(:general), do: ~p"/system/settings"

  def tab_path(tab) do
    slug = Enum.find_value(@tabs, fn {id, slug, _label, _icon} -> id == tab && slug end)
    ~p"/system/settings?#{[tab: slug]}"
  end

  attr :current, :atom, required: true
  attr :attention, :list, default: [], doc: "tab ids to mark as needing attention"

  @doc """
  The tab bar. Each tab is a patch link to its own URL rather than an ARIA
  tablist: they are real, bookmarkable addresses, so navigation semantics (and
  the back button) are the honest model, and there is no roving-tabindex keyboard
  contract to half-implement.
  """
  def settings_tabs(assigns) do
    ~H"""
    <nav aria-label="Settings sections" class="overflow-x-auto border-b border-base-content/10">
      <div class="tabs tabs-border flex-nowrap min-w-max">
        <.link
          :for={{id, slug, label, icon} <- tabs()}
          id={"settings-tab-#{slug}"}
          patch={tab_path(id)}
          aria-current={id == @current && "page"}
          class={[
            "tab gap-2 whitespace-nowrap transition-colors",
            if(id == @current,
              do: "tab-active font-semibold text-base-content",
              else: "text-base-content/60 hover:text-base-content"
            )
          ]}
        >
          <.icon name={icon} class="size-4" />
          {label}
          <span :if={id in @attention} class="size-2 rounded-full bg-warning" aria-hidden="true">
          </span>
          <span :if={id in @attention} class="sr-only">(needs attention)</span>
        </.link>
      </div>
    </nav>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :icon, :string, default: nil
  attr :class, :any, default: nil
  slot :description
  slot :actions, doc: "controls aligned to the right of the title, e.g. a badge or button"
  slot :inner_block, required: true

  @doc "A titled settings card. Every section on the page sits in one."
  def settings_card(assigns) do
    ~H"""
    <section
      id={@id}
      aria-labelledby={"#{@id}-title"}
      class={["card bg-base-200 border border-base-content/10", @class]}
    >
      <div class="card-body gap-4">
        <header class="flex flex-wrap items-start justify-between gap-3">
          <div class="min-w-0 space-y-1">
            <h2 id={"#{@id}-title"} class="card-title text-base font-semibold">
              <.icon :if={@icon} name={@icon} class="size-5 shrink-0" />
              {@title}
            </h2>
            <p :if={@description != []} class="text-sm text-base-content/60">
              {render_slot(@description)}
            </p>
          </div>
          <div :if={@actions != []} class="flex shrink-0 items-center gap-2">
            {render_slot(@actions)}
          </div>
        </header>
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  @doc "Stands in for an organization-scoped tab when no organization is in scope."
  def org_required(assigns) do
    ~H"""
    <section
      id="org-required"
      class="card border border-dashed border-base-content/15 bg-base-200/50"
    >
      <div class="card-body items-center gap-2 py-12 text-center">
        <.icon name="hero-building-office-2" class="size-7 text-base-content/50" />
        <h2 class="text-base font-semibold">No organization in scope</h2>
        <p class="max-w-md text-sm text-base-content/60">
          Members, API keys, security and branding are set per organization.
          Create or select an organization first.
        </p>
      </div>
    </section>
    """
  end
end
