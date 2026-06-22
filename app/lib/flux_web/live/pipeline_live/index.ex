defmodule FluxWeb.PipelineLive.Index do
  @moduledoc "LiveView for listing and managing pipelines."
  use FluxWeb, :live_view

  import FluxWeb.Authorization

  alias Flux.Pipelines
  alias Flux.Pipelines.PortableConfig
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
     |> assign(:show_import, false)
     |> allow_upload(:import,
       accept: ~w(.json application/json),
       max_entries: 1,
       max_file_size: 1_000_000
     )
     |> stream(:pipelines, pipelines)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold tracking-tight text-base-content">
            Pipelines
          </h1>
          <p class="text-base-content/60 mt-1">Manage your data transformation pipelines</p>
        </div>
        <div class="flex items-center gap-2">
          <button
            :if={can?(@current_scope, :create_pipeline)}
            phx-click="open_import"
            class="btn btn-ghost"
          >
            <.icon name="hero-arrow-up-tray" class="w-5 h-5" /> Import
          </button>
          <.link
            :if={can?(@current_scope, :create_pipeline)}
            navigate={~p"/pipelines/builder"}
            class="btn btn-primary"
          >
            <.icon name="hero-plus" class="w-5 h-5" /> New Pipeline
          </.link>
        </div>
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
                  <.pipeline_status_badge status={pipeline.status} />
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

      <div :if={@show_import} class="modal modal-open" id="import-modal">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Import Pipeline</h3>
          <p class="text-sm text-base-content/60 mt-1">
            Upload a pipeline JSON export. Referenced sinks must already exist in this organization.
          </p>
          <form id="import-form" phx-submit="import" phx-change="validate_import" class="mt-4">
            <.live_file_input upload={@uploads.import} class="file-input file-input-bordered w-full" />
            <p :for={err <- upload_errors(@uploads.import)} class="text-error text-sm mt-1">
              {error_to_string(err)}
            </p>
            <div class="modal-action">
              <button type="button" phx-click="close_import" class="btn btn-ghost">Cancel</button>
              <button type="submit" class="btn btn-primary" disabled={@uploads.import.entries == []}>
                Import
              </button>
            </div>
          </form>
        </div>
        <div class="modal-backdrop" phx-click="close_import"></div>
      </div>
    </div>
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
  def handle_event("open_import", _params, socket),
    do: {:noreply, assign(socket, :show_import, true)}

  def handle_event("close_import", _params, socket),
    do: {:noreply, assign(socket, :show_import, false)}

  def handle_event("validate_import", _params, socket), do: {:noreply, socket}

  def handle_event("import", _params, socket) do
    authorize(socket, :create_pipeline, fn ->
      org_id = socket.assigns.current_scope.organization_id

      [result] =
        consume_uploaded_entries(socket, :import, fn %{path: path}, _entry ->
          {:ok, do_import(File.read!(path), org_id)}
        end)

      case result do
        {:ok, pipeline} ->
          {:noreply,
           socket
           |> assign(:show_import, false)
           |> assign(:has_pipelines, true)
           |> stream_insert(:pipelines, pipeline, at: 0)
           |> put_flash(:info, "Imported pipeline \"#{pipeline.name}\"")}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:show_import, false)
           |> put_flash(:error, import_error_message(reason))}
      end
    end)
  end

  def handle_event("start", %{"id" => id}, socket) do
    authorize_pipeline(socket, id, :run_pipeline, fn pipeline ->
      case Manager.start_pipeline(pipeline.id) do
        {:ok, _pid} ->
          {:ok, pipeline} = Pipelines.update_status(pipeline, "active")
          {:noreply, stream_insert(socket, :pipelines, pipeline)}

        {:error, :rate_limited} ->
          {:noreply, put_flash(socket, :error, start_limit_message())}

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

        {:error, :rate_limited} ->
          {:noreply, put_flash(socket, :error, start_limit_message())}

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

  defp start_limit_message,
    do: "Too many pipeline starts — please wait a moment and try again."

  @impl true
  def handle_info({:pipeline_updated, pipeline}, socket) do
    {:noreply, stream_insert(socket, :pipelines, pipeline)}
  end

  defp do_import(contents, org_id) do
    case Jason.decode(contents) do
      {:ok, envelope} -> PortableConfig.import_pipeline(envelope, org_id)
      {:error, %Jason.DecodeError{}} -> {:error, {:invalid_format, "File is not valid JSON"}}
    end
  end

  defp import_error_message({:unsupported_version, version}),
    do: "Unsupported export version (#{version})."

  defp import_error_message({:invalid_format, message}), do: message
  defp import_error_message({:invalid_steps, message}), do: message

  defp import_error_message({:missing_sinks, names}),
    do:
      "These sinks don't exist in this organization: #{Enum.join(names, ", ")}. Create them first."

  defp import_error_message(%Ecto.Changeset{} = changeset) do
    # The only unique constraint on pipelines is (organization_id, name); the
    # error attaches to :organization_id, so detect the violation by constraint.
    if Enum.any?(changeset.errors, fn {_field, {_msg, opts}} -> opts[:constraint] == :unique end) do
      "A pipeline with that name already exists."
    else
      "Import failed: invalid pipeline data."
    end
  end

  defp error_to_string(:too_large), do: "File is too large (max 1 MB)."
  defp error_to_string(:not_accepted), do: "Only .json files are accepted."
  defp error_to_string(:too_many_files), do: "Only one file can be imported at a time."
  defp error_to_string(_), do: "Invalid file."
end
