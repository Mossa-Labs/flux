defmodule FluxWeb.DashboardLive.Index do
  @moduledoc "LiveView for the main dashboard showing pipeline metrics and system health."
  use FluxWeb, :live_view

  alias Flux.Pipelines
  alias Flux.Pipeline.Manager
  alias Flux.Pipeline.Metrics

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Flux.PubSub, Metrics.topic())
      Phoenix.PubSub.subscribe(Flux.PubSub, "pipelines")
    end

    org_id = socket.assigns.current_scope.organization_id
    snapshot = Metrics.snapshot()
    pipelines = Pipelines.list_pipelines(org_id)
    active_count = Enum.count(pipelines, &(&1.status == "active"))
    running_count = length(Manager.list_running())
    anomaly_count = length(Flux.AI.list_anomalous_pipelines())

    # Seed with this node's metrics; peers fold in as their broadcasts arrive.
    metrics_by_node = %{node() => Map.put(snapshot, :node, node())}

    {:ok,
     socket
     |> assign(:active_tab, :dashboard)
     |> assign(:page_title, "Dashboard")
     |> assign(:active_pipeline_count, active_count)
     |> assign(:running_pipeline_count, running_count)
     |> assign(:anomaly_count, anomaly_count)
     |> assign(:metrics_by_node, metrics_by_node)
     |> assign_cluster_metrics(metrics_by_node)}
  end

  @impl true
  def handle_info({:metrics_update, metrics}, socket) do
    node = Map.get(metrics, :node, node())

    metrics_by_node =
      socket.assigns.metrics_by_node
      |> Map.put(node, metrics)
      # Drop nodes that have left the cluster so their stale totals don't linger.
      |> Map.take([node() | Node.list()])

    {:noreply,
     socket
     |> assign(:metrics_by_node, metrics_by_node)
     |> assign_cluster_metrics(metrics_by_node)}
  end

  def handle_info({:pipeline_updated, _pipeline}, socket) do
    org_id = socket.assigns.current_scope.organization_id
    pipelines = Pipelines.list_pipelines(org_id)
    active_count = Enum.count(pipelines, &(&1.status == "active"))
    running_count = length(Manager.list_running())
    anomaly_count = length(Flux.AI.list_anomalous_pipelines())

    {:noreply,
     socket
     |> assign(:active_pipeline_count, active_count)
     |> assign(:running_pipeline_count, running_count)
     |> assign(:anomaly_count, anomaly_count)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # Fold per-node metrics into cluster-wide totals for display.
  defp assign_cluster_metrics(socket, metrics_by_node) do
    totals = Metrics.fold(Map.values(metrics_by_node))

    socket
    |> assign(:events_per_sec, totals.events_per_sec)
    |> assign(:processed_total, totals.processed_total)
    |> assign(:failed_total, totals.failed_total)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mb-6">
      <h1 class="text-2xl font-bold bg-gradient-to-r from-indigo-500 via-purple-500 to-pink-500 bg-clip-text text-transparent">
        Dashboard
      </h1>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
      <%!-- Active Pipelines --%>
      <div class="card bg-base-100 shadow-sm border border-base-200">
        <div class="card-body p-6">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-base-content/60">Active Pipelines</p>
              <p class="text-3xl font-bold mt-1">{@active_pipeline_count}</p>
            </div>
            <div class="p-3 bg-primary/10 rounded-xl text-primary">
              <.icon name="hero-queue-list" class="w-6 h-6" />
            </div>
          </div>
          <div class="mt-4 flex items-center text-sm text-base-content/60">
            <.icon name="hero-play-circle" class="w-4 h-4 mr-1" />
            <span>{@running_pipeline_count} running</span>
          </div>
        </div>
      </div>

      <%!-- Events/Sec --%>
      <div class="card bg-base-100 shadow-sm border border-base-200">
        <div class="card-body p-6">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-base-content/60">Events / Sec</p>
              <p class="text-3xl font-bold mt-1">{format_number(@events_per_sec)}</p>
            </div>
            <div class="p-3 bg-secondary/10 rounded-xl text-secondary">
              <.icon name="hero-bolt" class="w-6 h-6" />
            </div>
          </div>
          <div class="mt-4 flex items-center text-sm text-base-content/60">
            <span>{format_number(@processed_total)} processed</span>
          </div>
        </div>
      </div>

      <%!-- Anomalies --%>
      <div class="card bg-base-100 shadow-sm border border-base-200">
        <div class="card-body p-6">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-base-content/60">Anomalies</p>
              <p class={["text-3xl font-bold mt-1", @anomaly_count > 0 && "text-error"]}>
                {@anomaly_count}
              </p>
            </div>
            <div class="p-3 bg-error/10 rounded-xl text-error">
              <.icon name="hero-exclamation-triangle" class="w-6 h-6" />
            </div>
          </div>
          <div class="mt-4 flex items-center text-sm">
            <span :if={@anomaly_count > 0} class="text-error">
              <.icon name="hero-exclamation-circle" class="w-4 h-4 mr-1 inline" /> Requires attention
            </span>
            <span :if={@anomaly_count == 0} class="text-success">
              <.icon name="hero-check-circle" class="w-4 h-4 mr-1 inline" /> All clear
            </span>
          </div>
        </div>
      </div>

      <%!-- Failed Messages --%>
      <div class="card bg-base-100 shadow-sm border border-base-200">
        <div class="card-body p-6">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-base-content/60">Failed Messages</p>
              <p class={["text-3xl font-bold mt-1", @failed_total > 0 && "text-warning"]}>
                {format_number(@failed_total)}
              </p>
            </div>
            <div class="p-3 bg-warning/10 rounded-xl text-warning">
              <.icon name="hero-x-circle" class="w-6 h-6" />
            </div>
          </div>
          <div class="mt-4 flex items-center text-sm text-base-content/60">
            <span>Lifetime total</span>
          </div>
        </div>
      </div>
    </div>

    <%!-- System Health --%>
    <div class="card bg-base-100 shadow-sm border border-base-200">
      <div class="card-body">
        <h2 class="card-title text-base font-bold mb-4">System Health</h2>
        <div class="grid grid-cols-3 gap-6">
          <div class="text-center p-4 bg-base-200/30 rounded-lg">
            <p class="text-2xl font-bold text-primary">{format_number(@events_per_sec)}</p>
            <p class="text-sm text-base-content/60 mt-1">Events/sec</p>
          </div>
          <div class="text-center p-4 bg-base-200/30 rounded-lg">
            <p class="text-2xl font-bold text-success">{@active_pipeline_count}</p>
            <p class="text-sm text-base-content/60 mt-1">Active pipelines</p>
          </div>
          <div class="text-center p-4 bg-base-200/30 rounded-lg">
            <p class={[
              "text-2xl font-bold",
              if(@anomaly_count > 0, do: "text-error", else: "text-success")
            ]}>
              {@anomaly_count}
            </p>
            <p class="text-sm text-base-content/60 mt-1">Anomalies detected</p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_number(num) when is_float(num), do: :erlang.float_to_binary(num, decimals: 1)
  defp format_number(num) when is_integer(num), do: Integer.to_string(num)
  defp format_number(_), do: "0"
end
