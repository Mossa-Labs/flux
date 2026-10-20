defmodule FluxWeb.SystemSettingsLive.GeneralTab do
  @moduledoc """
  Usage & quotas and build information for System Settings.
  """
  use FluxWeb, :html

  alias FluxWeb.Components.UpgradePrompt

  attr :enabled, :boolean, required: true
  attr :usage, :map, default: nil

  def usage_section(assigns) do
    ~H"""
    <section class="card bg-base-100 shadow-sm border border-base-200">
      <div class="card-body">
        <h2 class="card-title text-base font-bold">
          <.icon name="hero-chart-bar" class="w-5 h-5" /> Usage & Quotas
        </h2>

        <%= cond do %>
          <% !@enabled -> %>
            <div class="mt-2">
              <UpgradePrompt.upgrade_prompt feature={:usage_metering} />
            </div>
          <% is_nil(@usage) -> %>
            <p class="text-sm text-base-content/60 mt-2">Usage data is not available yet.</p>
          <% true -> %>
            <.usage_body usage={@usage} />
        <% end %>
      </div>
    </section>
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
      <div :if={!Map.get(@quota, :unlimited, true)} class="space-y-1">
        <div class="flex items-center justify-between text-sm">
          <span class="text-base-content/70">
            Messages this period
            <span :if={Map.get(@quota, :state) == :warn} class="badge badge-warning badge-sm ml-1">
              {usage_pct(@quota)}% used
            </span>
            <span :if={Map.get(@quota, :state) == :over} class="badge badge-error badge-sm ml-1">
              over quota
            </span>
          </span>
          <span class="font-medium">
            {format_metric(:messages_ingested, Map.get(@quota, :usage, 0))} / {format_metric(
              :messages_ingested,
              Map.get(@quota, :limit)
            )}
          </span>
        </div>
        <div class="w-full bg-base-200 rounded-full h-2 overflow-hidden">
          <div
            class={["h-2 rounded-full", quota_bar_class(Map.get(@quota, :state))]}
            style={"width: #{quota_bar_width(@quota)}%"}
          >
          </div>
        </div>
      </div>

      <dl class="grid grid-cols-2 sm:grid-cols-5 gap-4">
        <div :for={metric <- Flux.Metering.metrics()} class="rounded-lg border border-base-200 p-3">
          <dt class="text-xs text-base-content/60">{usage_metric_label(metric)}</dt>
          <dd class="text-lg font-semibold">{format_metric(metric, Map.get(@metrics, metric))}</dd>
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
  def about_section(assigns) do
    assigns = assign(assigns, :build, Flux.BuildInfo.to_map())

    ~H"""
    <section class="card bg-base-100 shadow-sm border border-base-200">
      <div class="card-body">
        <div class="flex items-start justify-between gap-4">
          <div>
            <h2 class="card-title text-base-content">About this build</h2>
            <p class="text-sm text-base-content/60 mt-1">
              Quote this when contacting support.
            </p>
          </div>
          <button
            type="button"
            class="btn btn-sm btn-ghost gap-2"
            id="copy-build-info"
            phx-hook=".CopyBuildInfo"
            data-build={Flux.BuildInfo.long()}
          >
            <.icon name="hero-clipboard-document" class="w-4 h-4" /> Copy
          </button>
        </div>

        <dl class="mt-4 grid grid-cols-1 gap-x-6 gap-y-2 sm:grid-cols-2 text-sm">
          <div class="flex justify-between sm:block">
            <dt class="text-base-content/60">Edition</dt>
            <dd class="font-medium text-base-content">{@build.edition}</dd>
          </div>
          <div class="flex justify-between sm:block">
            <dt class="text-base-content/60">Version</dt>
            <dd class="font-medium text-base-content">{@build.version}</dd>
          </div>
          <div class="flex justify-between sm:block">
            <dt class="text-base-content/60">Core revision</dt>
            <dd class="font-mono text-xs text-base-content">{@build.core_sha}</dd>
          </div>
          <div :if={@build.edition_sha} class="flex justify-between sm:block">
            <dt class="text-base-content/60">Edition revision</dt>
            <dd class="font-mono text-xs text-base-content">{@build.edition_sha}</dd>
          </div>
          <div class="flex justify-between sm:block">
            <dt class="text-base-content/60">Toolchain</dt>
            <dd class="font-medium text-base-content">
              OTP {@build.otp} / Elixir {@build.elixir}
            </dd>
          </div>
          <div class="flex justify-between sm:block">
            <dt class="text-base-content/60">Built</dt>
            <dd class="font-medium text-base-content">{@build.built_at || "—"}</dd>
          </div>
        </dl>

        <p :if={not @build.released} class="mt-4 text-xs text-warning">
          <.icon name="hero-exclamation-triangle" class="w-4 h-4 inline-block align-text-bottom" />
          This build carries no source revision, so it was not produced by the release
          pipeline and cannot be reproduced from a tag.
        </p>
      </div>
    </section>

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
