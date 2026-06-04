defmodule FluxWeb.PipelineLive.Index do
  @moduledoc "LiveView for listing and managing pipelines."
  use FluxWeb, :live_view

  import FluxWeb.Authorization

  alias Flux.Pipelines
  alias Flux.Pipeline.Manager

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Flux.PubSub, "pipelines")
    end

    pipelines = Pipelines.list_pipelines(socket.assigns.current_scope.organization_id)

    {:ok,
     socket
     |> assign(:active_tab, :pipelines)
     |> assign(:page_title, "Pipelines")
     |> assign(:has_pipelines, pipelines != [])
     |> stream(:pipelines, pipelines)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold bg-gradient-to-r from-indigo-500 via-purple-500 to-pink-500 bg-clip-text text-transparent">
            Pipelines
          </h1>
          <p class="text-base-content/60 mt-1">Manage your data transformation pipelines</p>
        </div>
        <.link
          :if={can?(@current_scope, :create_pipeline)}
          navigate={~p"/pipelines/builder"}
          class="btn btn-primary"
        >
          <.icon name="hero-plus" class="w-5 h-5" /> New Pipeline
        </.link>
      </div>

      <div class="card bg-base-100 shadow-sm border border-base-200">
        <div class="card-body p-0">
          <div
            :if={!@has_pipelines}
            class="flex flex-col items-center justify-center py-16 text-center"
          >
            <div class="p-4 bg-base-200 rounded-full mb-4">
              <.icon name="hero-queue-list" class="w-12 h-12 text-base-content/40" />
            </div>
            <h3 class="text-lg font-semibold">No pipelines yet</h3>
            <p class="text-base-content/60 mt-2 max-w-md">
              Create your first pipeline to start transforming and routing data.
            </p>
            <.link
              :if={can?(@current_scope, :create_pipeline)}
              navigate={~p"/pipelines/builder"}
              class="btn btn-primary mt-6"
            >
              <.icon name="hero-plus" class="w-5 h-5" /> Create Pipeline
            </.link>
          </div>

          <table :if={@has_pipelines} class="table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Status</th>
                <th>Source Queue</th>
                <th>Sinks</th>
                <th>Updated</th>
                <th class="text-right">Actions</th>
              </tr>
            </thead>
            <tbody id="pipelines" phx-update="stream">
              <tr :for={{id, pipeline} <- @streams.pipelines} id={id} class="hover">
                <td>
                  <.link navigate={~p"/pipelines/#{pipeline.id}"} class="font-medium link link-hover">
                    {pipeline.name}
                  </.link>
                  <p :if={pipeline.description} class="text-sm text-base-content/60 truncate max-w-xs">
                    {pipeline.description}
                  </p>
                </td>
                <td>
                  <.status_badge status={pipeline.status} />
                </td>
                <td class="font-mono text-sm">{pipeline.source_queue}</td>
                <td>
                  <span class="badge badge-ghost">{length(pipeline.sink_ids || [])} sinks</span>
                </td>
                <td class="text-sm text-base-content/60">
                  {format_datetime(pipeline.updated_at)}
                </td>
                <td class="text-right">
                  <div class="flex items-center justify-end gap-2">
                    <.status_button pipeline={pipeline} />
                    <.link
                      navigate={~p"/pipelines/#{pipeline.id}/builder"}
                      class="btn btn-ghost btn-sm"
                      title="Edit in Builder"
                    >
                      <.icon name="hero-pencil-square" class="w-4 h-4" />
                    </.link>
                    <button
                      phx-click="delete"
                      phx-value-id={pipeline.id}
                      class="btn btn-ghost btn-sm text-error"
                      title="Delete"
                      data-confirm="Are you sure you want to delete this pipeline?"
                    >
                      <.icon name="hero-trash" class="w-4 h-4" />
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
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

  defp status_button(assigns) do
    ~H"""
    <div :if={@pipeline.status == "stopped"}>
      <button
        phx-click="start"
        phx-value-id={@pipeline.id}
        class="btn btn-ghost btn-sm text-success"
        title="Start"
      >
        <.icon name="hero-play" class="w-4 h-4" />
      </button>
    </div>
    <div :if={@pipeline.status == "active"}>
      <button
        phx-click="pause"
        phx-value-id={@pipeline.id}
        class="btn btn-ghost btn-sm text-warning"
        title="Pause"
      >
        <.icon name="hero-pause" class="w-4 h-4" />
      </button>
      <button
        phx-click="stop"
        phx-value-id={@pipeline.id}
        class="btn btn-ghost btn-sm text-error"
        title="Stop"
      >
        <.icon name="hero-stop" class="w-4 h-4" />
      </button>
    </div>
    <div :if={@pipeline.status == "paused"}>
      <button
        phx-click="resume"
        phx-value-id={@pipeline.id}
        class="btn btn-ghost btn-sm text-success"
        title="Resume"
      >
        <.icon name="hero-play" class="w-4 h-4" />
      </button>
      <button
        phx-click="stop"
        phx-value-id={@pipeline.id}
        class="btn btn-ghost btn-sm text-error"
        title="Stop"
      >
        <.icon name="hero-stop" class="w-4 h-4" />
      </button>
    </div>
    """
  end

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %H:%M")
  end

  @impl true
  def handle_event("start", %{"id" => id}, socket) do
    authorize_pipeline(socket, id, :run_pipeline, fn pipeline ->
      case Manager.start_pipeline(pipeline.id) do
        {:ok, _pid} ->
          {:ok, pipeline} = Pipelines.update_status(pipeline, "active")
          {:noreply, stream_insert(socket, :pipelines, pipeline)}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to start: #{inspect(reason)}")}
      end
    end)
  end

  def handle_event("pause", %{"id" => id}, socket) do
    authorize_pipeline(socket, id, :run_pipeline, fn pipeline ->
      Manager.stop_pipeline(pipeline.id)
      {:ok, pipeline} = Pipelines.update_status(pipeline, "paused")
      {:noreply, stream_insert(socket, :pipelines, pipeline)}
    end)
  end

  def handle_event("resume", %{"id" => id}, socket) do
    authorize_pipeline(socket, id, :run_pipeline, fn pipeline ->
      case Manager.start_pipeline(pipeline.id) do
        {:ok, _pid} ->
          {:ok, pipeline} = Pipelines.update_status(pipeline, "active")
          {:noreply, stream_insert(socket, :pipelines, pipeline)}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to resume: #{inspect(reason)}")}
      end
    end)
  end

  def handle_event("stop", %{"id" => id}, socket) do
    authorize_pipeline(socket, id, :run_pipeline, fn pipeline ->
      Manager.stop_pipeline(pipeline.id)
      {:ok, pipeline} = Pipelines.update_status(pipeline, "stopped")
      {:noreply, stream_insert(socket, :pipelines, pipeline)}
    end)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    authorize_pipeline(socket, id, :delete_pipeline, fn pipeline ->
      if pipeline.status == "active" do
        Manager.stop_pipeline(pipeline.id)
      end

      {:ok, _} = Pipelines.delete_pipeline(pipeline)

      {:noreply,
       socket
       |> stream_delete(:pipelines, pipeline)
       |> put_flash(:info, "Pipeline deleted")}
    end)
  end

  # Authorizes `action` for the current role, then loads the pipeline scoped to
  # the current organization (so a crafted id from another org is treated as
  # not-found). Calls `fun.(pipeline)` only when both checks pass.
  defp authorize_pipeline(socket, id, action, fun) do
    authorize(socket, action, fn ->
      case Pipelines.get_pipeline(id, socket.assigns.current_scope.organization_id) do
        nil -> {:noreply, put_flash(socket, :error, "Pipeline not found.")}
        pipeline -> fun.(pipeline)
      end
    end)
  end

  @impl true
  def handle_info({:pipeline_updated, pipeline}, socket) do
    {:noreply, stream_insert(socket, :pipelines, pipeline)}
  end
end
