defmodule FluxWeb.SystemSettingsLive.BrandingTab do
  @moduledoc """
  The Branding tab of System Settings: white-label name, colour and assets.
  """
  use FluxWeb, :html

  import FluxWeb.SystemSettingsLive.Components

  alias FluxWeb.Components.Brand
  alias FluxWeb.Components.UpgradePrompt

  attr :enabled, :boolean, required: true
  attr :branding, :map, required: true
  attr :form, :any, required: true
  attr :uploads, :any, required: true

  def branding_tab(assigns) do
    ~H"""
    <.settings_card id="branding-card" title="Branding" icon="hero-paint-brush">
      <:description>Replace the Flux name and accent colour with your own.</:description>

      <%= if @enabled do %>
        <div class="grid gap-6 lg:grid-cols-5 lg:items-start">
          <%!-- phx-change is required for live_file_input to stage entries. --%>
          <.form
            for={@form}
            id="branding-form"
            phx-change="validate_branding"
            phx-submit="save_branding"
            class="space-y-3 lg:col-span-3"
          >
            <div class="grid gap-x-3 sm:grid-cols-3">
              <div class="sm:col-span-2">
                <.input field={@form[:brand_name]} type="text" label="Brand name" maxlength="40" />
              </div>
              <.input field={@form[:primary_color]} type="color" label="Accent colour" />
            </div>
            <.input
              field={@form[:login_message]}
              type="textarea"
              label="Sign-in message"
              placeholder="Shown to everyone on the sign-in page"
            />

            <div class="grid gap-4 sm:grid-cols-2">
              <.asset_input
                upload={@uploads.logo}
                label="Logo"
                hint="PNG, up to 256 KB and 4096×4096. Replaces the tile in the header."
              />
              <.asset_input
                upload={@uploads.favicon}
                label="Favicon"
                hint="PNG, up to 256 KB. Shown in the browser tab."
              />
            </div>

            <div class="flex flex-wrap items-center gap-3 pt-1">
              <.button class="btn btn-primary btn-sm">Save branding</.button>
              <p class="text-xs text-base-content/60">
                The accent colour and icon apply on the next full page load.
              </p>
            </div>
          </.form>

          <%!--
          A preview rather than a live preview. The chrome only re-reads
          branding on a full page load, so showing the saved result here is
          honest; animating it as you type would imply the header updates too.
          --%>
          <aside aria-label="Currently applied" class="space-y-2 lg:col-span-2">
            <p class="text-xs font-medium text-base-content/60">Currently applied</p>
            <div class="flex items-center justify-center rounded-box border border-base-content/5 bg-base-300 px-4 py-8">
              <Brand.brand_mark branding={@branding} />
            </div>
          </aside>
        </div>
      <% else %>
        <UpgradePrompt.upgrade_prompt feature={:white_label} size={:compact} />
      <% end %>
    </.settings_card>
    """
  end

  attr :upload, :any, required: true
  attr :label, :string, required: true
  attr :hint, :string, required: true

  defp asset_input(assigns) do
    ~H"""
    <div>
      <label for={@upload.ref} class="text-sm font-medium">{@label}</label>
      <p class="mb-1 text-xs text-base-content/60">{@hint}</p>
      <.live_file_input upload={@upload} class="file-input file-input-sm w-full" />
      <p :for={err <- upload_errors(@upload)} class="mt-1 text-xs text-error">
        {upload_error_message(err)}
      </p>
      <p :for={entry <- @upload.entries} class="mt-1 text-xs text-base-content/60">
        {entry.client_name}
        <span :for={err <- upload_errors(@upload, entry)} class="text-error">
          — {upload_error_message(err)}
        </span>
      </p>
    </div>
    """
  end

  defp upload_error_message(:too_large), do: "is larger than 256 KB"
  defp upload_error_message(:not_accepted), do: "must be a PNG"
  defp upload_error_message(:too_many_files), do: "— only one file"
  defp upload_error_message(err), do: "could not be uploaded (#{inspect(err)})"
end
