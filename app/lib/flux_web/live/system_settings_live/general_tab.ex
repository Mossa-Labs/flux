defmodule FluxWeb.SystemSettingsLive.GeneralTab do
  @moduledoc """
  The General tab of System Settings: the License card, Usage & quotas, and
  build information.
  """
  use FluxWeb, :html

  import FluxWeb.SystemSettingsLive.Components

  alias FluxWeb.Components.UpgradePrompt
  alias FluxWeb.SystemSettingsLive.LicenseCard

  attr :license, :map, required: true
  attr :activation_supported, :boolean, default: false
  attr :license_form, :any, default: nil
  attr :node_states, :list, default: []
  attr :node_capacity, :any, default: nil
  attr :usage_metering_enabled, :boolean, required: true
  attr :usage, :map, default: nil

  def general_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <LicenseCard.license_card
        license={@license}
        activation_supported={@activation_supported}
        license_form={@license_form}
        node_states={@node_states}
        node_capacity={@node_capacity}
      />
      <.usage_section enabled={@usage_metering_enabled} usage={@usage} />
      <.about_section />
    </div>
    """
  end

  attr :enabled, :boolean, required: true
  attr :usage, :map, default: nil

  defp usage_section(assigns) do
    ~H"""
    <.settings_card id="usage-card" title="Usage & quotas" icon="hero-chart-bar">
      <%= cond do %>
        <% !@enabled -> %>
          <UpgradePrompt.upgrade_prompt feature={:usage_metering} />
        <% is_nil(@usage) -> %>
          <p class="text-sm text-base-content/60">Usage data is not available yet.</p>
        <% true -> %>
          <.usage_body usage={@usage} />
      <% end %>
    </.settings_card>
    """
  end

  attr :usage, :map, required: true

  defp usage_body(assigns) do
    assigns =
      assigns
      |> assign(:metrics, Map.get(assigns.usage, :metrics, %{}))
      |> assign(:quota, Map.get(assigns.usage, :quota, %{}))

    ~H"""
    <div class="space-y-4">
      <div :if={!Map.get(@quota, :unlimited, true)} class="space-y-1.5">
        <div class="flex flex-wrap items-center justify-between gap-2 text-sm">
          <span class="text-base-content/70">
            Messages this period
            <span :if={Map.get(@quota, :state) == :warn} class="badge badge-warning badge-sm ml-1">
              {usage_pct(@quota)}% used
            </span>
            <span :if={Map.get(@quota, :state) == :over} class="badge badge-error badge-sm ml-1">
              over quota
            </span>
          </span>
          <span class="font-medium tabular-nums">
            {format_metric(:messages_ingested, Map.get(@quota, :usage, 0))} / {format_metric(
              :messages_ingested,
              Map.get(@quota, :limit)
            )}
          </span>
        </div>
        <div class="h-1.5 w-full overflow-hidden rounded-full bg-base-300">
          <div
            class={["h-full rounded-full transition-all", quota_bar_class(Map.get(@quota, :state))]}
            style={"width: #{quota_bar_width(@quota)}%"}
          >
          </div>
        </div>
      </div>

      <dl class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
        <div
          :for={metric <- Flux.Metering.metrics()}
          class="rounded-box border border-base-content/5 bg-base-300 px-4 py-3"
        >
          <dt class="text-xs text-base-content/60">{usage_metric_label(metric)}</dt>
          <dd class="mt-0.5 text-xl font-semibold tabular-nums">
            {format_metric(metric, Map.get(@metrics, metric))}
          </dd>
        </div>
      </dl>
    </div>
    """
  end

  defp usage_metric_label(:messages_ingested), do: "Ingested"
  defp usage_metric_label(:messages_processed), do: "Processed"
  defp usage_metric_label(:sink_deliveries), do: "Sink deliveries"
  defp usage_metric_label(:active_pipelines), do: "Active pipelines"
  defp usage_metric_label(:pipeline_hours), do: "Pipeline hours"

  defp format_metric(_metric, nil), do: "∞"

  defp format_metric(:pipeline_hours, value) when is_number(value),
    do: :erlang.float_to_binary(value / 1, decimals: 1)

  defp format_metric(_metric, value) when is_integer(value), do: delimit(value)
  defp format_metric(_metric, value), do: to_string(value)

  # Group integer digits with commas (e.g. 12345 -> "12,345"); avoids a dep.
  defp delimit(value) when is_integer(value) do
    sign = if value < 0, do: "-", else: ""

    digits =
      value
      |> abs()
      |> Integer.to_string()
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.map_join(",", &Enum.join/1)
      |> String.reverse()

    sign <> digits
  end

  defp usage_pct(quota), do: quota |> Map.get(:pct, 0.0) |> round()

  defp quota_bar_width(quota) do
    quota |> Map.get(:pct, 0.0) |> min(100.0) |> max(0.0) |> Float.round(1)
  end

  defp quota_bar_class(:over), do: "bg-error"
  defp quota_bar_class(:warn), do: "bg-warning"
  defp quota_bar_class(_), do: "bg-primary"

  # Full build identity, behind auth. The footer carries version + revision for
  # everyone; the toolchain and exact build time sit here because an
  # unauthenticated, precisely-versioned instance is easier to match against
  # published CVEs.
  defp about_section(assigns) do
    assigns = assign(assigns, :build, Flux.BuildInfo.to_map())

    ~H"""
    <.settings_card id="about-card" title="About this build" icon="hero-code-bracket">
      <:description>Quote this when contacting support.</:description>
      <:actions>
        <button
          type="button"
          class="btn btn-sm btn-ghost gap-2"
          id="copy-build-info"
          phx-hook=".CopyBuildInfo"
          data-build={Flux.BuildInfo.long()}
        >
          <.icon name="hero-clipboard-document" class="size-4" /> Copy
        </button>
      </:actions>

      <dl class="grid grid-cols-1 gap-x-8 gap-y-3 text-sm sm:grid-cols-2 lg:grid-cols-3">
        <div>
          <dt class="text-xs text-base-content/60">Edition</dt>
          <dd class="font-medium">{@build.edition}</dd>
        </div>
        <div>
          <dt class="text-xs text-base-content/60">Version</dt>
          <dd class="font-medium">{@build.version}</dd>
        </div>
        <div>
          <dt class="text-xs text-base-content/60">Core revision</dt>
          <dd class="font-mono text-xs">{@build.core_sha}</dd>
        </div>
        <div :if={@build.edition_sha}>
          <dt class="text-xs text-base-content/60">Edition revision</dt>
          <dd class="font-mono text-xs">{@build.edition_sha}</dd>
        </div>
        <div>
          <dt class="text-xs text-base-content/60">Toolchain</dt>
          <dd class="font-medium">OTP {@build.otp} / Elixir {@build.elixir}</dd>
        </div>
        <div>
          <dt class="text-xs text-base-content/60">Built</dt>
          <dd class="font-medium">{@build.built_at || "—"}</dd>
        </div>
      </dl>

      <p :if={not @build.released} class="flex items-start gap-2 text-xs text-warning">
        <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
        This build carries no source revision, so it was not produced by the release
        pipeline and cannot be reproduced from a tag.
      </p>
    </.settings_card>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyBuildInfo">
      export default {
        mounted() {
          this.el.addEventListener("click", () => {
            navigator.clipboard.writeText(this.el.dataset.build).then(() => {
              const original = this.el.innerHTML
              this.el.textContent = "Copied"
              setTimeout(() => { this.el.innerHTML = original }, 1500)
            })
          })
        }
      }
    </script>
    """
  end
end
