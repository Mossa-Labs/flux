defmodule FluxWeb.SystemSettingsLive.BrandingTab do
  @moduledoc """
  White-label branding for System Settings.
  """
  use FluxWeb, :html

  alias FluxWeb.Components.Brand
  alias FluxWeb.Components.UpgradePrompt

  attr :enabled, :boolean, required: true
  attr :branding, :map, required: true
  attr :form, :any, required: true
  attr :uploads, :any, required: true

  def branding_section(assigns) do
    ~H"""
    <section class="card bg-base-100 shadow-sm border border-base-200">
      <div class="card-body">
        <h2 class="card-title text-base font-bold">
          <.icon name="hero-paint-brush" class="w-5 h-5" /> Branding
        </h2>
        <p class="text-sm text-base-content/60">
          Replace the Flux name and accent colour with your own.
        </p>

        <%= if @enabled do %>
          <%!-- phx-change is required for live_file_input to stage entries. --%>
          <.form
            for={@form}
            id="branding-form"
            phx-change="validate_branding"
            phx-submit="save_branding"
            class="mt-2 space-y-3"
          >
            <.input field={@form[:brand_name]} type="text" label="Brand name" maxlength="40" />
            <.input
              field={@form[:primary_color]}
              type="color"
              label="Accent colour"
            />
            <.input
              field={@form[:login_message]}
              type="textarea"
              label="Sign-in message"
              placeholder="Shown to everyone on the sign-in page"
            />

            <div>
              <label class="text-sm font-medium">Logo</label>
              <p class="text-xs text-base-content/60 mb-1">
                PNG, up to 256 KB and 4096×4096. Replaces the tile in the header.
              </p>
              <.live_file_input upload={@uploads.logo} class="file-input file-input-sm w-full" />
              <p :for={err <- upload_errors(@uploads.logo)} class="mt-1 text-xs text-error">
                {upload_error_message(err)}
              </p>
              <p
                :for={entry <- @uploads.logo.entries}
                class="mt-1 text-xs text-base-content/60"
              >
                {entry.client_name}
                <span :for={err <- upload_errors(@uploads.logo, entry)} class="text-error">
                  — {upload_error_message(err)}
                </span>
              </p>
            </div>

            <div>
              <label class="text-sm font-medium">Favicon</label>
              <p class="text-xs text-base-content/60 mb-1">
                PNG, up to 256 KB. Shown in the browser tab.
              </p>
              <.live_file_input upload={@uploads.favicon} class="file-input file-input-sm w-full" />
              <p :for={err <- upload_errors(@uploads.favicon)} class="mt-1 text-xs text-error">
                {upload_error_message(err)}
              </p>
              <p
                :for={entry <- @uploads.favicon.entries}
                class="mt-1 text-xs text-base-content/60"
              >
                {entry.client_name}
                <span :for={err <- upload_errors(@uploads.favicon, entry)} class="text-error">
                  — {upload_error_message(err)}
                </span>
              </p>
            </div>

            <%!--
            A preview rather than a live preview. The chrome only re-reads
            branding on a full page load, so showing the saved result here is
            honest; animating it as you type would imply the header updates too.
            --%>
            <div class="rounded-lg border border-base-200 p-3">
              <p class="text-xs text-base-content/60 mb-2">Currently applied</p>
              <Brand.brand_mark branding={@branding} />
            </div>

            <p class="text-xs text-base-content/60">
              The accent colour and icon apply on the next full page load.
            </p>

            <.button class="btn btn-primary btn-sm">Save branding</.button>
          </.form>
        <% else %>
          <UpgradePrompt.upgrade_prompt feature={:white_label} size={:compact} />
        <% end %>
      </div>
    </section>
    """
  end

  defp upload_error_message(:too_large), do: "is larger than 256 KB"
  defp upload_error_message(:not_accepted), do: "must be a PNG"
  defp upload_error_message(:too_many_files), do: "— only one logo"
  defp upload_error_message(err), do: "could not be uploaded (#{inspect(err)})"
end
