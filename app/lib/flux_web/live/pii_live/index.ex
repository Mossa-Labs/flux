defmodule FluxWeb.PIILive.Index do
  @moduledoc """
  Enterprise-gated PII redaction dashboard (MOS-480).

  Shows redaction activity for the organization — PII types over time, the
  redaction rate, and a per-field breakdown — served by the active
  `Flux.PII.Provider`. Community builds resolve to the no-op provider and see an
  upgrade prompt.

  The dashboard is read-only and metadata-only: it renders counts sourced from
  `[:flux, :pii, :redaction]` telemetry aggregated by the Enterprise
  `Flux.PII.Aggregator`. No raw PII ever reaches this view.
  """
  use FluxWeb, :live_view

  alias Flux.PII
  alias FluxWeb.Components.UpgradePrompt

  @refresh_ms 5_000
  @window_seconds 3_600
  @bucket_seconds 300

  @pii_type_labels %{
    "email" => "Email",
    "phone" => "Phone",
    "ssn" => "SSN",
    "credit_card" => "Credit card",
    "name" => "Name",
    "address" => "Address"
  }

  @impl true
  def mount(_params, _session, socket) do
    entitled? = Flux.License.has_feature?(:pii_redaction)

    if connected?(socket) and entitled?, do: Process.send_after(self(), :refresh, @refresh_ms)

    {:ok,
     socket
     |> assign(:active_tab, :redaction)
     |> assign(:page_title, "PII Redaction")
     |> assign(:pii_entitled, entitled?)
     |> assign(:stats, empty_stats())
     |> load_stats()}
  end

  defp load_stats(%{assigns: %{pii_entitled: true}} = socket) do
    org_id = socket.assigns.current_scope.organization_id

    stats =
      PII.stats(org_id, nil, window_seconds: @window_seconds, bucket_seconds: @bucket_seconds)

    assign(socket, :stats, stats)
  end

  defp load_stats(socket), do: socket

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, load_stats(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-2xl font-bold tracking-tight text-base-content">PII Redaction</h1>
        <p class="text-base-content/60 mt-1">
          In-flight PII detection and masking across your pipelines — types redacted, rate, and per-field breakdown
        </p>
      </div>

      <UpgradePrompt.upgrade_prompt :if={!@pii_entitled} feature={:pii_redaction} />

      <div
        :if={@pii_entitled && @stats.totals.messages_scanned == 0}
        class="card bg-base-100 shadow-sm border border-base-200"
      >
        <div class="card-body flex flex-col items-center justify-center py-16 text-center">
          <div class="p-4 bg-base-200 rounded-full mb-4">
            <.icon name="hero-shield-check" class="w-12 h-12 text-base-content/40" />
          </div>
          <h3 class="text-lg font-semibold">No redactions yet</h3>
          <p class="text-base-content/60 mt-2 max-w-md">
            Add a <span class="font-medium">Redact</span>
            step to a pipeline. As messages flow through, redaction activity shows up here.
          </p>
        </div>
      </div>

      <div :if={@pii_entitled && @stats.totals.messages_scanned > 0} class="space-y-6">
        <%!-- Summary stat tiles --%>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <.stat_tile
            id="stat-scanned"
            label="Messages scanned"
            value={format_int(@stats.totals.messages_scanned)}
            icon="hero-magnifying-glass"
          />
          <.stat_tile
            id="stat-redacted"
            label="Messages redacted"
            value={format_int(@stats.totals.messages_redacted)}
            icon="hero-shield-check"
          />
          <.stat_tile
            id="stat-rate"
            label="Redaction rate"
            value={format_rate(@stats.totals.redaction_rate)}
            icon="hero-chart-bar"
          />
          <.stat_tile
            id="stat-instances"
            label="PII instances masked"
            value={format_int(@stats.totals.pii_instances)}
            icon="hero-lock-closed"
          />
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <%!-- PII types breakdown --%>
          <div class="card bg-base-100 shadow-sm border border-base-200">
            <div class="card-body">
              <h3 class="text-lg font-semibold mb-4">PII types detected</h3>
              <div class="space-y-3">
                <div :for={{type, count} <- sorted_by_type(@stats.by_type)} class="space-y-1">
                  <div class="flex items-center justify-between text-sm">
                    <span class="font-medium">{type_label(type)}</span>
                    <span class="text-base-content/60 tabular-nums">{format_int(count)}</span>
                  </div>
                  <div class="h-2 w-full rounded-full bg-base-200 overflow-hidden">
                    <div
                      class="h-full rounded-full bg-primary transition-all duration-500"
                      style={"width: #{bar_pct(count, max_type_count(@stats.by_type))}%"}
                    >
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <%!-- Per-field breakdown --%>
          <div class="card bg-base-100 shadow-sm border border-base-200">
            <div class="card-body">
              <h3 class="text-lg font-semibold mb-4">Per-field breakdown</h3>
              <div class="overflow-x-auto">
                <table class="table table-sm w-full">
                  <thead>
                    <tr>
                      <th>Field</th>
                      <th class="text-right">PII instances</th>
                      <th>Types</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={{field, detail} <- sorted_by_field(@stats.by_field)}>
                      <td class="font-mono text-xs">{field}</td>
                      <td class="text-right tabular-nums">{format_int(detail.count)}</td>
                      <td>
                        <div class="flex flex-wrap gap-1">
                          <span
                            :for={{t, _c} <- detail.by_type}
                            class="badge badge-sm badge-ghost"
                          >
                            {type_label(t)}
                          </span>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>

        <%!-- Timeline --%>
        <div class="card bg-base-100 shadow-sm border border-base-200">
          <div class="card-body">
            <h3 class="text-lg font-semibold mb-4">Redactions over time</h3>
            <div class="flex items-end gap-1 h-40">
              <div
                :for={bucket <- @stats.timeline}
                class="flex-1 flex flex-col items-center justify-end group relative"
                title={"#{format_int(bucket.messages_redacted)} redacted"}
              >
                <div
                  class="w-full rounded-t bg-primary/80 group-hover:bg-primary transition-all"
                  style={"height: #{bar_pct(bucket.messages_redacted, max_timeline(@stats.timeline))}%"}
                >
                </div>
              </div>
            </div>
            <div class="flex justify-between text-xs text-base-content/50 mt-2">
              <span>{format_time(@stats.window.from)}</span>
              <span>{format_time(@stats.window.to)}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :icon, :string, required: true

  defp stat_tile(assigns) do
    ~H"""
    <div id={@id} class="card bg-base-100 shadow-sm border border-base-200">
      <div class="card-body p-4">
        <div class="flex items-center gap-3">
          <div class="p-2 rounded-lg bg-primary/10">
            <.icon name={@icon} class="w-5 h-5 text-primary" />
          </div>
          <div>
            <p class="text-xs text-base-content/60">{@label}</p>
            <p class="text-xl font-bold tabular-nums">{@value}</p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── formatting helpers ──────────────────────────────────────────────────────

  defp empty_stats do
    now = DateTime.utc_now()

    %{
      window: %{
        from: DateTime.add(now, -@window_seconds, :second),
        to: now,
        bucket_seconds: @bucket_seconds
      },
      totals: %{messages_scanned: 0, messages_redacted: 0, redaction_rate: 0.0, pii_instances: 0},
      by_type: %{},
      by_field: %{},
      timeline: []
    }
  end

  defp type_label(type), do: Map.get(@pii_type_labels, type, type)

  defp sorted_by_type(by_type) do
    Enum.sort_by(by_type, fn {_type, count} -> count end, :desc)
  end

  defp sorted_by_field(by_field) do
    Enum.sort_by(by_field, fn {_field, detail} -> detail.count end, :desc)
  end

  defp max_type_count(by_type) when map_size(by_type) == 0, do: 0
  defp max_type_count(by_type), do: by_type |> Map.values() |> Enum.max()

  defp max_timeline([]), do: 0

  defp max_timeline(timeline) do
    timeline |> Enum.map(& &1.messages_redacted) |> Enum.max()
  end

  defp bar_pct(_count, 0), do: 0
  defp bar_pct(count, max), do: round(count / max * 100)

  defp format_int(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end

  defp format_int(n), do: to_string(n)

  defp format_rate(rate) when is_float(rate) do
    "#{Float.round(rate * 100, 1)}%"
  end

  defp format_rate(_), do: "0%"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M")
  end

  defp format_time(_), do: ""
end
