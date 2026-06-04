defmodule FluxWeb.SinkLive.Index do
  @moduledoc "LiveView for listing and managing sink destinations."
  use FluxWeb, :live_view

  import FluxWeb.Authorization

  alias Flux.Sinks

  @impl true
  def mount(_params, _session, socket) do
    sinks = Sinks.list_sinks(socket.assigns.current_scope.organization_id)

    {:ok,
     socket
     |> assign(:active_tab, :sinks)
     |> assign(:page_title, "Sinks")
     |> assign(:has_sinks, sinks != [])
     |> stream(:sinks, sinks)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold bg-gradient-to-r from-indigo-500 via-purple-500 to-pink-500 bg-clip-text text-transparent">
            Sinks
          </h1>
          <p class="text-base-content/60 mt-1">Configure output destinations for your pipelines</p>
        </div>
        <.link
          :if={can?(@current_scope, :create_sink)}
          navigate={~p"/sinks/new"}
          class="btn btn-primary"
        >
          <.icon name="hero-plus" class="w-5 h-5" /> New Sink
        </.link>
      </div>

      <div class="card bg-base-100 shadow-sm border border-base-200">
        <div class="card-body p-0">
          <div
            :if={!@has_sinks}
            class="flex flex-col items-center justify-center py-16 text-center"
          >
            <div class="p-4 bg-base-200 rounded-full mb-4">
              <.icon name="hero-server-stack" class="w-12 h-12 text-base-content/40" />
            </div>
            <h3 class="text-lg font-semibold">No sinks configured</h3>
            <p class="text-base-content/60 mt-2 max-w-md">
              Create sinks to send your transformed data to external destinations like webhooks, S3, or databases.
            </p>
            <.link
              :if={can?(@current_scope, :create_sink)}
              navigate={~p"/sinks/new"}
              class="btn btn-primary mt-6"
            >
              <.icon name="hero-plus" class="w-5 h-5" /> Create Sink
            </.link>
          </div>

          <table :if={@has_sinks} class="table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Type</th>
                <th>Status</th>
                <th>Updated</th>
                <th class="text-right">Actions</th>
              </tr>
            </thead>
            <tbody id="sinks" phx-update="stream">
              <tr :for={{id, sink} <- @streams.sinks} id={id} class="hover">
                <td>
                  <div class="flex items-center gap-3">
                    <.sink_icon type={sink.type} />
                    <div>
                      <p class="font-medium">{sink.name}</p>
                      <p :if={sink.description} class="text-sm text-base-content/60 truncate max-w-xs">
                        {sink.description}
                      </p>
                    </div>
                  </div>
                </td>
                <td>
                  <.type_badge type={sink.type} />
                </td>
                <td>
                  <span :if={sink.enabled} class="badge badge-success">Enabled</span>
                  <span :if={!sink.enabled} class="badge badge-ghost">Disabled</span>
                </td>
                <td class="text-sm text-base-content/60">
                  {format_datetime(sink.updated_at)}
                </td>
                <td class="text-right">
                  <div class="flex items-center justify-end gap-2">
                    <button
                      phx-click="test"
                      phx-value-id={sink.id}
                      class="btn btn-ghost btn-sm"
                      title="Test Connection"
                    >
                      <.icon name="hero-signal" class="w-4 h-4" />
                    </button>
                    <button
                      phx-click="toggle"
                      phx-value-id={sink.id}
                      class="btn btn-ghost btn-sm"
                      title={if sink.enabled, do: "Disable", else: "Enable"}
                    >
                      <.icon
                        name={if sink.enabled, do: "hero-pause", else: "hero-play"}
                        class="w-4 h-4"
                      />
                    </button>
                    <.link
                      navigate={~p"/sinks/#{sink.id}/edit"}
                      class="btn btn-ghost btn-sm"
                      title="Edit"
                    >
                      <.icon name="hero-pencil" class="w-4 h-4" />
                    </.link>
                    <button
                      phx-click="delete"
                      phx-value-id={sink.id}
                      class="btn btn-ghost btn-sm text-error"
                      title="Delete"
                      data-confirm="Are you sure you want to delete this sink?"
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
    <div class="p-2 bg-primary/10 rounded-lg text-primary">
      <.icon name={@icon} class="w-5 h-5" />
    </div>
    """
  end

  defp type_badge(assigns) do
    {color, label} =
      case assigns.type do
        "http" -> {"badge-info", "HTTP"}
        "s3" -> {"badge-secondary", "S3"}
        "postgres" -> {"badge-accent", "Postgres"}
        _ -> {"badge-ghost", String.upcase(assigns.type)}
      end

    assigns = assign(assigns, color: color, label: label)

    ~H"""
    <span class={"badge #{@color}"}>{@label}</span>
    """
  end

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %H:%M")
  end

  @impl true
  def handle_event("test", %{"id" => id}, socket) do
    sink = Sinks.get_sink!(id)

    case Sinks.test_connection(sink) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Connection successful!")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Connection failed: #{inspect(reason)}")}
    end
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    authorize(socket, :edit_sink, fn ->
      sink = Sinks.get_sink!(id)
      {:ok, sink} = Sinks.toggle_enabled(sink)
      status = if sink.enabled, do: "enabled", else: "disabled"

      {:noreply,
       socket
       |> stream_insert(:sinks, sink)
       |> put_flash(:info, "Sink #{status}")}
    end)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    authorize(socket, :delete_sink, fn ->
      sink = Sinks.get_sink!(id)
      {:ok, _} = Sinks.delete_sink(sink)

      {:noreply,
       socket
       |> stream_delete(:sinks, sink)
       |> put_flash(:info, "Sink deleted")}
    end)
  end
end
