defmodule FluxWeb.AnomalyLive.Index do
  @moduledoc "LiveView for real-time anomaly detection and signal monitoring."
  use FluxWeb, :live_view

  alias Flux.AI.Scorer
  alias Flux.Pipeline.Manager
  alias Flux.Pipelines
  alias FluxWeb.Components.UpgradePrompt

  @refresh_interval_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    entitled? = Flux.License.has_feature?(:live_signals)

    if entitled? and connected?(socket) do
      :timer.send_interval(@refresh_interval_ms, self(), :refresh)
    end

    org_id = socket.assigns.current_scope.organization_id
    anomaly_data = if entitled?, do: build_anomaly_data(org_id), else: []

    {:ok,
     socket
     |> assign(:active_tab, :signals)
     |> assign(:page_title, "Live Signals")
     |> assign(:live_signals_entitled, entitled?)
     |> assign(:anomaly_data, anomaly_data)
     |> assign(:selected_pipeline_id, nil)
     |> assign(:selected_fields, [])}
  end

  @impl true
  def handle_info(:refresh, socket) do
    org_id = socket.assigns.current_scope.organization_id
    anomaly_data = build_anomaly_data(org_id)

    socket =
      socket
      |> assign(:anomaly_data, anomaly_data)
      |> maybe_refresh_chart()

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("select_pipeline", %{"id" => id}, socket) do
    fields = build_field_details(id)

    socket =
      socket
      |> assign(:selected_pipeline_id, id)
      |> assign(:selected_fields, fields)
      |> push_chart_data(id)

    {:noreply, socket}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_pipeline_id, nil)
     |> assign(:selected_fields, [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-2xl font-bold bg-gradient-to-r from-indigo-500 via-purple-500 to-pink-500 bg-clip-text text-transparent">
          Live Signals
        </h1>
        <p class="text-base-content/60 mt-1">AI-powered anomaly detection across your pipelines</p>
      </div>

      <UpgradePrompt.upgrade_prompt :if={!@live_signals_entitled} feature={:live_signals} />

      <%!-- Summary Bar --%>
      <div :if={@live_signals_entitled} class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div class="card bg-base-100 shadow-sm border border-base-200">
          <div class="card-body p-4 flex-row items-center gap-3">
            <div class={[
              "p-2 rounded-lg",
              anomaly_total(@anomaly_data) > 0 && "bg-error/10 text-error",
              anomaly_total(@anomaly_data) == 0 && "bg-success/10 text-success"
            ]}>
              <.icon name="hero-exclamation-triangle" class="w-5 h-5" />
            </div>
            <div>
              <p class="text-2xl font-bold">{anomaly_total(@anomaly_data)}</p>
              <p class="text-sm text-base-content/60">Active anomalies</p>
            </div>
          </div>
        </div>
        <div class="card bg-base-100 shadow-sm border border-base-200">
          <div class="card-body p-4 flex-row items-center gap-3">
            <div class="p-2 rounded-lg bg-primary/10 text-primary">
              <.icon name="hero-chart-bar" class="w-5 h-5" />
            </div>
            <div>
              <p class="text-2xl font-bold">{format_score(highest_score(@anomaly_data))}</p>
              <p class="text-sm text-base-content/60">Highest z-score</p>
            </div>
          </div>
        </div>
        <div class="card bg-base-100 shadow-sm border border-base-200">
          <div class="card-body p-4 flex-row items-center gap-3">
            <div class="p-2 rounded-lg bg-secondary/10 text-secondary">
              <.icon name="hero-cpu-chip" class="w-5 h-5" />
            </div>
            <div>
              <p class="text-2xl font-bold">{length(@anomaly_data)}</p>
              <p class="text-sm text-base-content/60">Pipelines monitored</p>
            </div>
          </div>
        </div>
      </div>

      <%!-- Pipeline Anomaly Table --%>
      <div :if={@live_signals_entitled} class="card bg-base-100 shadow-sm border border-base-200">
        <div class="card-body p-0">
          <div
            :if={@anomaly_data == []}
            class="flex flex-col items-center justify-center py-16 text-center"
          >
            <div class="p-4 bg-base-200 rounded-full mb-4">
              <.icon name="hero-cpu-chip" class="w-12 h-12 text-base-content/40" />
            </div>
            <h3 class="text-lg font-semibold">No active signals</h3>
            <p class="text-base-content/60 mt-2 max-w-md">
              Start a pipeline with anomaly detection enabled to see AI signals here.
            </p>
          </div>

          <table :if={@anomaly_data != []} class="table">
            <thead>
              <tr>
                <th>Pipeline</th>
                <th>Status</th>
                <th>Max Z-Score</th>
                <th>Fields</th>
                <th>Signal</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={entry <- @anomaly_data}
                class={[
                  "hover cursor-pointer transition-colors",
                  @selected_pipeline_id == entry.pipeline_id && "bg-base-200/50"
                ]}
                phx-click="select_pipeline"
                phx-value-id={entry.pipeline_id}
              >
                <td class="font-medium">{entry.pipeline_name}</td>
                <td>
                  <.pipeline_status_badge status={entry.status} />
                </td>
                <td>
                  <span class={["font-mono text-sm font-semibold", score_color(entry.max_score)]}>
                    {format_score(entry.max_score)}
                  </span>
                </td>
                <td>
                  <span class="badge badge-ghost">{entry.field_count} fields</span>
                </td>
                <td>
                  <div :if={entry.anomaly} class="flex items-center gap-1 text-error">
                    <span class="relative flex h-2.5 w-2.5">
                      <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-error opacity-75">
                      </span>
                      <span class="relative inline-flex rounded-full h-2.5 w-2.5 bg-error"></span>
                    </span>
                    <span class="text-sm font-medium">Anomaly</span>
                  </div>
                  <div :if={!entry.anomaly} class="flex items-center gap-1 text-success">
                    <span class="inline-flex rounded-full h-2.5 w-2.5 bg-success"></span>
                    <span class="text-sm">Normal</span>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%!-- Detail Panel --%>
      <div :if={@selected_pipeline_id} class="card bg-base-100 shadow-sm border border-base-200">
        <div class="card-body">
          <div class="flex items-center justify-between mb-4">
            <h2 class="card-title text-base font-bold">
              <.icon name="hero-magnifying-glass-circle" class="w-5 h-5" /> Field Breakdown
            </h2>
            <button phx-click="close_detail" class="btn btn-ghost btn-sm btn-circle">
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </button>
          </div>

          <div :if={@selected_fields == []} class="text-center py-8 text-base-content/40">
            No field data available for this pipeline.
          </div>

          <table :if={@selected_fields != []} class="table table-sm mb-6">
            <thead>
              <tr>
                <th>Field</th>
                <th>Z-Score</th>
                <th>Count</th>
                <th>Min</th>
                <th>Max</th>
                <th>Signal</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={field <- @selected_fields}>
                <td class="font-mono text-sm">{field.name}</td>
                <td>
                  <span class={["font-mono text-sm font-semibold", score_color(field.z_score)]}>
                    {format_score(field.z_score)}
                  </span>
                </td>
                <td class="text-sm">{field.count}</td>
                <td class="font-mono text-sm">{format_score(field.min)}</td>
                <td class="font-mono text-sm">{format_score(field.max)}</td>
                <td>
                  <span :if={field.anomaly} class="badge badge-error badge-sm">Anomaly</span>
                  <span :if={!field.anomaly} class="badge badge-success badge-sm">Normal</span>
                </td>
              </tr>
            </tbody>
          </table>

          <%!-- Chart --%>
          <h3 class="font-semibold text-sm mb-2">Value History</h3>
          <div
            id="anomaly-chart"
            phx-hook="AnomalyChart"
            phx-update="ignore"
            class="w-full min-h-[300px] rounded-lg border border-base-200 bg-base-200/20 p-2"
          >
            <div class="flex items-center justify-center h-[300px] text-base-content/40">
              Loading chart...
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # -- Private helpers --

  defp build_anomaly_data(org_id) do
    running_ids = Manager.list_running()
    pipelines = Pipelines.list_pipelines(org_id)

    for pipeline <- pipelines,
        pipeline.id in running_ids do
      fields = Flux.AI.list_fields(pipeline.id)

      field_scores =
        for field <- fields do
          case Flux.AI.get_stats(pipeline.id, field) do
            {:ok, stats} ->
              latest = List.last(stats.values)
              z = if latest, do: Scorer.z_score(latest, stats), else: 0.0
              %{anomaly: abs(z) > 2.0, z_score: z}

            {:error, _} ->
              nil
          end
        end
        |> Enum.reject(&is_nil/1)

      max_score =
        field_scores
        |> Enum.map(& &1.z_score)
        |> Enum.map(&abs/1)
        |> Enum.max(fn -> 0.0 end)

      %{
        pipeline_id: pipeline.id,
        pipeline_name: pipeline.name,
        status: pipeline.status,
        max_score: max_score,
        anomaly: Enum.any?(field_scores, & &1.anomaly),
        field_count: length(fields)
      }
    end
    |> Enum.sort_by(& &1.max_score, :desc)
  end

  defp build_field_details(pipeline_id) do
    fields = Flux.AI.list_fields(pipeline_id)

    for field <- fields do
      case Flux.AI.get_stats(pipeline_id, field) do
        {:ok, stats} ->
          latest = List.last(stats.values)
          z = if latest, do: Scorer.z_score(latest, stats), else: 0.0

          %{
            name: field,
            z_score: z,
            count: stats.count,
            min: stats.min,
            max: stats.max,
            anomaly: abs(z) > 2.0
          }

        {:error, _} ->
          nil
      end
    end
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&abs(&1.z_score), :desc)
  end

  defp push_chart_data(socket, pipeline_id) do
    fields = Flux.AI.list_fields(pipeline_id)

    {series, labels} =
      Enum.reduce(fields, {[], []}, fn field, {series_acc, labels_acc} ->
        case Flux.AI.get_stats(pipeline_id, field) do
          {:ok, %{values: values}} when values != [] ->
            {[values | series_acc], [field | labels_acc]}

          _ ->
            {series_acc, labels_acc}
        end
      end)

    if series == [] do
      socket
    else
      max_len = series |> Enum.map(&length/1) |> Enum.max()
      timestamps = Enum.to_list(0..(max_len - 1))

      padded_series =
        Enum.map(series, fn s ->
          pad_len = max_len - length(s)
          List.duplicate(nil, pad_len) ++ s
        end)

      push_event(socket, "chart-data", %{
        series: padded_series,
        labels: Enum.reverse(labels),
        timestamps: timestamps
      })
    end
  end

  defp maybe_refresh_chart(socket) do
    if socket.assigns.selected_pipeline_id do
      fields = build_field_details(socket.assigns.selected_pipeline_id)

      socket
      |> assign(:selected_fields, fields)
      |> push_chart_data(socket.assigns.selected_pipeline_id)
    else
      socket
    end
  end

  defp pipeline_status_badge(assigns) do
    {color, label} =
      case assigns.status do
        "active" -> {"badge-success", "Active"}
        "paused" -> {"badge-warning", "Paused"}
        "stopped" -> {"badge-ghost", "Stopped"}
        _ -> {"badge-ghost", assigns.status}
      end

    assigns = assign(assigns, color: color, label: label)

    ~H"""
    <span class={"badge #{@color}"}>{@label}</span>
    """
  end

  defp score_color(score) when is_number(score) do
    cond do
      abs(score) > 3.0 -> "text-error"
      abs(score) > 2.0 -> "text-warning"
      true -> "text-success"
    end
  end

  defp score_color(_), do: "text-base-content/60"

  defp format_score(num) when is_float(num), do: :erlang.float_to_binary(num, decimals: 2)
  defp format_score(num) when is_integer(num), do: Integer.to_string(num)
  defp format_score(_), do: "0.00"

  defp anomaly_total(data), do: Enum.count(data, & &1.anomaly)

  defp highest_score(data) do
    data
    |> Enum.map(& &1.max_score)
    |> Enum.max(fn -> 0.0 end)
  end
end
