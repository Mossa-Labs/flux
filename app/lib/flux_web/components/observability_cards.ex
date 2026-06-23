defmodule FluxWeb.Components.ObservabilityCards do
  @moduledoc """
  Shared function components for rendering per-source observability health
  (MOS-472): freshness SLO, volume baseline, and schema drift.

  Used by both the standalone `/observability` fleet page
  (`FluxWeb.ObservabilityLive.Index`) and the per-pipeline Observability tab
  (`FluxWeb.PipelineLive.Show`). The data is a source-health map as documented in
  `Flux.Observability.Provider`. The standalone page renders the freshness SLO
  config form (`editable={true}`); the pipeline tab renders read-only cards.
  """

  use Phoenix.Component

  alias FluxWeb.CoreComponents

  attr :health, :map, required: true, doc: "a source-health map (see Flux.Observability.Provider)"

  attr :editable, :boolean,
    default: false,
    doc: "when true, render the freshness SLO config form (standalone page only)"

  def source_card(assigns) do
    ~H"""
    <div
      id={"observability-source-#{@health.source}"}
      class="card bg-base-100 shadow-sm border border-base-200"
    >
      <div class="card-body">
        <div class="flex items-center gap-2">
          <CoreComponents.icon name="hero-inbox-arrow-down" class="w-5 h-5 text-primary" />
          <h2 class="card-title text-base font-mono">{@health.source}</h2>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mt-2">
          <.freshness_panel health={@health} editable={@editable} />
          <.volume_panel volume={@health.volume} />
          <.schema_panel schema={@health.schema} />
        </div>
      </div>
    </div>
    """
  end

  defp freshness_panel(assigns) do
    assigns = assign(assigns, :f, assigns.health.freshness)

    ~H"""
    <div class="rounded-lg border border-base-200 p-4">
      <div class="flex items-center justify-between">
        <span class="text-sm font-semibold text-base-content/70">Freshness</span>
        <.state_badge state={@f.state} labels={freshness_labels()} />
      </div>
      <dl class="mt-3 space-y-1 text-sm">
        <div class="flex justify-between">
          <dt class="text-base-content/60">Last seen</dt>
          <dd>{relative_time(@f.last_seen_at)}</dd>
        </div>
        <div class="flex justify-between">
          <dt class="text-base-content/60">SLO window</dt>
          <dd>{duration(@f.expected_interval_seconds)}</dd>
        </div>
      </dl>

      <.form
        :if={@editable}
        for={%{}}
        as={:slo}
        phx-submit="save_slo"
        class="mt-3 flex items-end gap-2"
      >
        <input type="hidden" name="slo[source]" value={@health.source} />
        <label class="form-control w-full">
          <span class="label-text text-xs">Expected interval (s)</span>
          <input
            type="number"
            name="slo[expected_interval_seconds]"
            min="1"
            value={@f.expected_interval_seconds}
            class="input input-bordered input-sm"
          />
        </label>
        <button type="submit" class="btn btn-sm btn-primary">Save</button>
      </.form>
    </div>
    """
  end

  defp volume_panel(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-200 p-4">
      <div class="flex items-center justify-between">
        <span class="text-sm font-semibold text-base-content/70">Volume</span>
        <.state_badge state={@volume.state} labels={volume_labels()} />
      </div>
      <dl class="mt-3 space-y-1 text-sm">
        <div class="flex justify-between">
          <dt class="text-base-content/60">Last minute</dt>
          <dd>{round_rate(@volume.current_rate)}/min</dd>
        </div>
        <div class="flex justify-between">
          <dt class="text-base-content/60">Baseline</dt>
          <dd>{round_rate(@volume.baseline_rate)}/min</dd>
        </div>
      </dl>
    </div>
    """
  end

  defp schema_panel(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-200 p-4">
      <div class="flex items-center justify-between">
        <span class="text-sm font-semibold text-base-content/70">Schema</span>
        <.state_badge state={@schema.state} labels={schema_labels()} />
      </div>
      <dl class="mt-3 space-y-1 text-sm">
        <div class="flex justify-between">
          <dt class="text-base-content/60">Fields</dt>
          <dd>{@schema.field_count || "—"}</dd>
        </div>
        <div class="flex justify-between">
          <dt class="text-base-content/60">Last drift</dt>
          <dd>{relative_time(@schema.last_drift_at)}</dd>
        </div>
      </dl>
    </div>
    """
  end

  attr :state, :atom, required: true
  attr :labels, :map, required: true

  defp state_badge(assigns) do
    {label, class} = Map.get(assigns.labels, assigns.state, {"Unknown", "badge-ghost"})
    assigns = assign(assigns, label: label, class: class)

    ~H"""
    <span class={["badge badge-sm", @class]}>{@label}</span>
    """
  end

  defp freshness_labels do
    %{
      ok: {"On time", "badge-success"},
      warn: {"Late", "badge-warning"},
      breach: {"Breached", "badge-error"},
      unknown: {"No data", "badge-ghost"}
    }
  end

  defp volume_labels do
    %{
      ok: {"Steady", "badge-success"},
      spike: {"Spike", "badge-warning"},
      drop: {"Drop", "badge-error"},
      unknown: {"No data", "badge-ghost"}
    }
  end

  defp schema_labels do
    %{
      ok: {"Stable", "badge-success"},
      drift: {"Drift", "badge-warning"},
      unknown: {"No data", "badge-ghost"}
    }
  end

  defp round_rate(n) when is_integer(n), do: n
  defp round_rate(n) when is_float(n), do: n |> Float.round(1) |> trim_float()
  defp round_rate(_), do: "0"

  defp trim_float(f) do
    if f == Float.round(f), do: trunc(f), else: f
  end

  defp duration(nil), do: "not set"
  defp duration(seconds) when seconds < 60, do: "#{seconds}s"
  defp duration(seconds) when seconds < 3600, do: "#{div(seconds, 60)}m"
  defp duration(seconds), do: "#{div(seconds, 3600)}h"

  defp relative_time(%DateTime{} = dt) do
    seconds = DateTime.diff(DateTime.utc_now(), dt)

    cond do
      seconds < 5 -> "just now"
      seconds < 60 -> "#{seconds}s ago"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3600)}h ago"
      true -> Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
    end
  end

  defp relative_time(_), do: "—"
end
