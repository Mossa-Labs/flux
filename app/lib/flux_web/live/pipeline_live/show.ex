defmodule FluxWeb.PipelineLive.Show do
  @moduledoc "LiveView for viewing pipeline details, configuration, and sinks."
  use FluxWeb, :live_view

  import FluxWeb.Authorization

  alias Flux.Pipelines
  alias Flux.Sinks
  alias Flux.Pipeline.Manager

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    pipeline = Pipelines.get_pipeline(id, socket.assigns.current_scope.organization_id)

    if pipeline do
      sinks =
        if pipeline.sink_ids && length(pipeline.sink_ids) > 0 do
          Sinks.get_sinks_by_ids(pipeline.sink_ids)
        else
          []
        end

      {:ok,
       socket
       |> assign(:active_tab, :pipelines)
       |> assign(:page_title, pipeline.name)
       |> assign(:pipeline, pipeline)
       |> assign(:sinks, sinks)}
    else
      {:ok,
       socket
       |> put_flash(:error, "Pipeline not found")
       |> push_navigate(to: ~p"/pipelines")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-4">
          <.link navigate={~p"/pipelines"} class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="w-4 h-4" />
          </.link>
          <div>
            <div class="flex items-center gap-3">
              <h1 class="text-2xl font-bold bg-gradient-to-r from-indigo-500 via-purple-500 to-pink-500 bg-clip-text text-transparent">
                {@pipeline.name}
              </h1>
              <.status_badge status={@pipeline.status} />
            </div>
            <p :if={@pipeline.description} class="text-base-content/60 mt-1">
              {@pipeline.description}
            </p>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <.status_actions pipeline={@pipeline} />
          <.link navigate={~p"/pipelines/#{@pipeline.id}/builder"} class="btn btn-primary btn-sm">
            <.icon name="hero-pencil-square" class="w-4 h-4" /> Edit in Builder
          </.link>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div class="lg:col-span-2 space-y-6">
          <div class="card bg-base-100 shadow-sm border border-base-200">
            <div class="card-body">
              <h2 class="card-title text-base">Configuration</h2>
              <div class="grid grid-cols-2 gap-4 mt-4">
                <div>
                  <label class="text-sm font-medium text-base-content/60">Source Queue</label>
                  <p class="font-mono mt-1">{@pipeline.source_queue}</p>
                </div>
                <div>
                  <label class="text-sm font-medium text-base-content/60">Destination Queue</label>
                  <p class="font-mono mt-1">{@pipeline.destination_queue || "—"}</p>
                </div>
                <div>
                  <label class="text-sm font-medium text-base-content/60">Created</label>
                  <p class="mt-1">{format_datetime(@pipeline.inserted_at)}</p>
                </div>
                <div>
                  <label class="text-sm font-medium text-base-content/60">Last Updated</label>
                  <p class="mt-1">{format_datetime(@pipeline.updated_at)}</p>
                </div>
              </div>
            </div>
          </div>

          <div class="card bg-base-100 shadow-sm border border-base-200">
            <div class="card-body">
              <h2 class="card-title text-base">Pipeline Steps</h2>
              <div class="mt-4">
                <.steps_preview steps={@pipeline.steps} />
              </div>
            </div>
          </div>
        </div>

        <div class="space-y-6">
          <div class="card bg-base-100 shadow-sm border border-base-200">
            <div class="card-body">
              <h2 class="card-title text-base">Sinks</h2>
              <div :if={@sinks == []} class="mt-4 text-center py-6">
                <p class="text-base-content/60">No sinks configured</p>
                <.link
                  navigate={~p"/pipelines/#{@pipeline.id}/builder"}
                  class="btn btn-sm btn-ghost mt-2"
                >
                  Add sinks in Builder
                </.link>
              </div>
              <ul :if={@sinks != []} class="mt-4 space-y-3">
                <li
                  :for={sink <- @sinks}
                  class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg"
                >
                  <.sink_icon type={sink.type} />
                  <div class="flex-1 min-w-0">
                    <p class="font-medium truncate">{sink.name}</p>
                    <p class="text-sm text-base-content/60">{String.upcase(sink.type)}</p>
                  </div>
                  <span :if={sink.enabled} class="badge badge-success badge-sm">Active</span>
                  <span :if={!sink.enabled} class="badge badge-ghost badge-sm">Disabled</span>
                </li>
              </ul>
            </div>
          </div>

          <div class="card bg-base-100 shadow-sm border border-base-200">
            <div class="card-body">
              <h2 class="card-title text-base">Danger Zone</h2>
              <div class="mt-4">
                <button
                  phx-click="delete"
                  class="btn btn-error btn-outline btn-sm w-full"
                  data-confirm="Are you sure you want to delete this pipeline? This action cannot be undone."
                >
                  <.icon name="hero-trash" class="w-4 h-4" /> Delete Pipeline
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp status_badge(assigns) do
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

  defp status_actions(assigns) do
    ~H"""
    <div :if={@pipeline.status == "stopped"}>
      <button phx-click="start" class="btn btn-success btn-sm">
        <.icon name="hero-play" class="w-4 h-4" /> Start
      </button>
    </div>
    <div :if={@pipeline.status == "active"} class="flex gap-2">
      <button phx-click="pause" class="btn btn-warning btn-sm">
        <.icon name="hero-pause" class="w-4 h-4" /> Pause
      </button>
      <button phx-click="stop" class="btn btn-error btn-sm btn-outline">
        <.icon name="hero-stop" class="w-4 h-4" /> Stop
      </button>
    </div>
    <div :if={@pipeline.status == "paused"} class="flex gap-2">
      <button phx-click="resume" class="btn btn-success btn-sm">
        <.icon name="hero-play" class="w-4 h-4" /> Resume
      </button>
      <button phx-click="stop" class="btn btn-error btn-sm btn-outline">
        <.icon name="hero-stop" class="w-4 h-4" /> Stop
      </button>
    </div>
    """
  end

  defp steps_preview(assigns) do
    steps =
      case assigns.steps do
        %{"steps" => steps} when is_list(steps) -> steps
        _ -> []
      end

    assigns = assign(assigns, steps: steps)

    ~H"""
    <div :if={@steps == []} class="text-center py-6 text-base-content/60">
      No transformation steps configured
    </div>
    <div :if={@steps != []} class="space-y-2">
      <div
        :for={step <- @steps}
        class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg"
      >
        <.step_icon type={step["type"]} operation={step["operation"]} />
        <div class="flex-1 min-w-0">
          <p class="font-medium">{step["operation"] || step["type"]}</p>
          <p class="text-sm text-base-content/60 truncate">
            {summarize_step_config(step)}
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp step_icon(assigns) do
    icon =
      case {assigns.type, assigns.operation} do
        {"native", "filter"} -> "hero-funnel"
        {"native", "map"} -> "hero-arrow-path"
        {"native", "rename"} -> "hero-pencil"
        {"script", _} -> "hero-code-bracket"
        {"ai", _} -> "hero-cpu-chip"
        _ -> "hero-cog-6-tooth"
      end

    assigns = assign(assigns, icon: icon)

    ~H"""
    <div class="p-2 bg-primary/10 rounded-lg text-primary">
      <.icon name={@icon} class="w-5 h-5" />
    </div>
    """
  end

  defp sink_icon(assigns) do
    icon =
      case assigns.type do
        "http" -> "hero-globe-alt"
        "s3" -> "hero-cloud-arrow-up"
        "postgres" -> "hero-circle-stack"
        _ -> "hero-server-stack"
      end

    assigns = assign(assigns, icon: icon)

    ~H"""
    <div class="p-2 bg-secondary/10 rounded-lg text-secondary">
      <.icon name={@icon} class="w-5 h-5" />
    </div>
    """
  end

  defp summarize_step_config(%{"config" => config}) when is_map(config) do
    config
    |> Map.take(["field", "fields", "from", "to", "operator"])
    |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
    |> Enum.join(", ")
    |> case do
      "" -> "No configuration"
      summary -> summary
    end
  end

  defp summarize_step_config(_), do: "No configuration"

  defp start_limit_message,
    do: "Too many pipeline starts — please wait a moment and try again."

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %H:%M")
  end

  @impl true
  def handle_event("start", _params, socket) do
    authorize(socket, :run_pipeline, fn ->
      pipeline = socket.assigns.pipeline

      case Manager.start_pipeline(pipeline.id) do
        {:ok, _pid} ->
          {:ok, pipeline} = Pipelines.update_status(pipeline, "active")
          {:noreply, assign(socket, :pipeline, pipeline)}

        {:error, :rate_limited} ->
          {:noreply, put_flash(socket, :error, start_limit_message())}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to start: #{inspect(reason)}")}
      end
    end)
  end

  def handle_event("pause", _params, socket) do
    authorize(socket, :run_pipeline, fn ->
      pipeline = socket.assigns.pipeline
      Manager.stop_pipeline(pipeline.id)
      {:ok, pipeline} = Pipelines.update_status(pipeline, "paused")
      {:noreply, assign(socket, :pipeline, pipeline)}
    end)
  end

  def handle_event("resume", _params, socket) do
    authorize(socket, :run_pipeline, fn ->
      pipeline = socket.assigns.pipeline

      case Manager.start_pipeline(pipeline.id) do
        {:ok, _pid} ->
          {:ok, pipeline} = Pipelines.update_status(pipeline, "active")
          {:noreply, assign(socket, :pipeline, pipeline)}

        {:error, :rate_limited} ->
          {:noreply, put_flash(socket, :error, start_limit_message())}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to resume: #{inspect(reason)}")}
      end
    end)
  end

  def handle_event("stop", _params, socket) do
    authorize(socket, :run_pipeline, fn ->
      pipeline = socket.assigns.pipeline
      Manager.stop_pipeline(pipeline.id)
      {:ok, pipeline} = Pipelines.update_status(pipeline, "stopped")
      {:noreply, assign(socket, :pipeline, pipeline)}
    end)
  end

  def handle_event("delete", _params, socket) do
    authorize(socket, :delete_pipeline, fn ->
      pipeline = socket.assigns.pipeline

      if pipeline.status == "active" do
        Manager.stop_pipeline(pipeline.id)
      end

      {:ok, _} = Pipelines.delete_pipeline(pipeline)

      {:noreply,
       socket
       |> put_flash(:info, "Pipeline deleted")
       |> push_navigate(to: ~p"/pipelines")}
    end)
  end
end
