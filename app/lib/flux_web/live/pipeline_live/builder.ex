defmodule FluxWeb.PipelineLive.Builder do
  @moduledoc "LiveView for the visual pipeline builder with React Flow canvas."
  use FluxWeb, :live_view

  import FluxWeb.Authorization

  alias Flux.Pipelines
  alias Flux.Pipelines.Pipeline
  alias Flux.Sinks

  @impl true
  def mount(params, _session, socket) do
    {pipeline, action} = load_or_create_pipeline(params, socket.assigns.current_scope)
    available_sinks = Sinks.list_enabled_sinks(socket.assigns.current_scope.organization_id)

    initial_ir = pipeline.steps || default_ir()

    {:ok,
     socket
     |> assign(:action, action)
     |> assign(:pipeline, pipeline)
     |> assign(:pipeline_name, pipeline.name || "New Pipeline")
     |> assign(:available_sinks, available_sinks)
     |> assign(:initial_ir, initial_ir)
     |> assign(:selected_node, nil)
     |> assign(:selected_edge, nil)
     |> assign(:advanced_ai, Flux.License.has_feature?(:advanced_ai))
     |> assign(:page_title, "Pipeline Builder")}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full flex">
      <%!-- Sidebar with node palette --%>
      <div class="w-64 bg-base-100 border-r border-base-300 flex flex-col">
        <div class="p-4 border-b border-base-300">
          <h2 class="font-semibold text-sm text-base-content/60 uppercase tracking-wider">Nodes</h2>
        </div>
        <div class="flex-1 overflow-y-auto p-4 space-y-2">
          <.node_item type="source" icon="hero-arrow-down-tray" label="Source" />
          <.node_item type="filter" icon="hero-funnel" label="Filter" />
          <.node_item type="map" icon="hero-arrow-path" label="Transform" />
          <.node_item type="rename" icon="hero-pencil" label="Rename" />
          <.node_item type="script" icon="hero-code-bracket" label="Script" />
          <.node_item type="anomaly" icon="hero-cpu-chip" label="AI Detect" />

          <div class="divider text-xs">Outputs</div>

          <.node_item type="queue" icon="hero-queue-list" label="Queue" />

          <%= for sink <- @available_sinks do %>
            <.sink_node_item sink={sink} />
          <% end %>

          <.link
            :if={@available_sinks == []}
            navigate={~p"/sinks/new"}
            class="btn btn-ghost btn-sm w-full justify-start text-base-content/60"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> Add Sink
          </.link>
        </div>
      </div>

      <%!-- Main canvas area --%>
      <div class="flex-1 flex flex-col">
        <%!-- Pipeline config bar --%>
        <div class="h-14 bg-base-100 border-b border-base-300 flex items-center px-4 gap-4">
          <.input_field
            name="pipeline_name"
            value={@pipeline_name}
            placeholder="Pipeline name"
            blur_event="update_name"
          />
          <div class="flex-1" />
          <button phx-click="save" class="btn btn-primary btn-sm">
            <.icon name="hero-check" class="w-4 h-4" /> Save Pipeline
          </button>
        </div>

        <%!-- Canvas placeholder for React Flow --%>
        <div
          id="pipeline-builder"
          phx-hook="PipelineBuilder"
          phx-update="ignore"
          data-initial-ir={Jason.encode!(@initial_ir)}
          data-available-sinks={Jason.encode!(Enum.map(@available_sinks, &sink_to_json/1))}
          data-pipeline-id={@pipeline.id}
          class="flex-1 bg-base-200"
        >
          <div class="h-full flex items-center justify-center text-base-content/40">
            <div class="text-center">
              <.icon name="hero-square-3-stack-3d" class="w-16 h-16 mx-auto mb-4" />
              <p class="text-lg font-medium">Visual Pipeline Builder</p>
              <p class="text-sm mt-2">Drag nodes from the sidebar to build your pipeline</p>
              <p class="text-xs mt-4 text-base-content/30">React Flow integration coming soon</p>
            </div>
          </div>
        </div>
      </div>

      <%!-- Right sidebar for node config --%>
      <div class="w-80 bg-base-100 border-l border-base-300 flex flex-col relative z-50">
        <div class="p-4 border-b border-base-300">
          <h2 class="font-semibold text-xs text-base-content/50 uppercase tracking-widest">
            Configuration
          </h2>
        </div>
        <div class="flex-1 overflow-y-auto p-4">
          <%= cond do %>
            <% @selected_node -> %>
              <.node_config_form node={@selected_node} advanced_ai={@advanced_ai} />
            <% @selected_edge -> %>
              <.edge_config_form edge={@selected_edge} ir={@initial_ir} />
            <% true -> %>
              <.empty_config_state />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp node_item(assigns) do
    ~H"""
    <div
      class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg cursor-grab hover:bg-base-200 transition-colors"
      draggable="true"
      data-node-type={@type}
    >
      <div class="p-2 bg-primary/10 rounded-lg text-primary">
        <.icon name={@icon} class="w-5 h-5" />
      </div>
      <span class="font-medium text-sm">{@label}</span>
    </div>
    """
  end

  defp sink_node_item(assigns) do
    icon =
      case assigns.sink.type do
        "http" -> "hero-globe-alt"
        "s3" -> "hero-cloud-arrow-up"
        "postgres" -> "hero-circle-stack"
        _ -> "hero-server-stack"
      end

    assigns = assign(assigns, :icon, icon)

    ~H"""
    <div
      class="flex items-center gap-3 p-3 bg-secondary/5 rounded-lg cursor-grab hover:bg-secondary/10 transition-colors"
      draggable="true"
      data-node-type="sink"
      data-sink-id={@sink.id}
    >
      <div class="p-2 bg-secondary/10 rounded-lg text-secondary">
        <.icon name={@icon} class="w-5 h-5" />
      </div>
      <div class="flex-1 min-w-0">
        <span class="font-medium text-sm truncate block">{@sink.name}</span>
        <span class="text-xs text-base-content/60">{String.upcase(@sink.type)}</span>
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :placeholder, :string, default: ""
  attr :blur_event, :string, required: true

  defp input_field(assigns) do
    ~H"""
    <input
      type="text"
      name={@name}
      value={@value}
      placeholder={@placeholder}
      phx-blur={@blur_event}
      class="input input-bordered input-sm w-48"
    />
    """
  end

  defp load_or_create_pipeline(%{"id" => id}, scope) do
    case Pipelines.get_pipeline(id, scope.organization_id) do
      nil -> {%Pipeline{organization_id: scope.organization_id}, :new}
      pipeline -> {pipeline, :edit}
    end
  end

  defp load_or_create_pipeline(_params, scope) do
    {%Pipeline{organization_id: scope.organization_id, steps: default_ir()}, :new}
  end

  defp default_ir do
    %{
      "version" => "1.0",
      "steps" => [],
      "nodes" => [
        %{
          "id" => "source",
          "type" => "source",
          "label" => "Source",
          "position" => %{"x" => 250, "y" => 50},
          "sourceConfig" => %{
            "type" => "queue",
            "queue" => "events.incoming",
            "prefetchCount" => 10,
            "ackMode" => "auto"
          }
        },
        %{
          "id" => "output",
          "type" => "sink",
          "label" => "Queue Output",
          "position" => %{"x" => 250, "y" => 170},
          "sinkType" => "queue",
          "queue" => "events.processed"
        }
      ],
      "edges" => [
        %{
          "id" => "source->output",
          "source" => "source",
          "target" => "output"
        }
      ]
    }
  end

  defp sink_to_json(sink) do
    %{
      id: sink.id,
      name: sink.name,
      type: sink.type,
      enabled: sink.enabled
    }
  end

  # ── Empty / placeholder states ────────────────────────────────────

  defp empty_config_state(assigns) do
    ~H"""
    <p class="text-sm text-base-content/60 text-center py-8">
      Select a node to configure
    </p>
    """
  end

  # ── Node config form router ───────────────────────────────────────

  defp node_config_form(%{node: %{type: "source"}} = assigns),
    do: ~H"<.source_config node={@node} />"

  defp node_config_form(%{node: %{type: "step"}} = assigns),
    do: ~H"<.step_config node={@node} advanced_ai={@advanced_ai} />"

  defp node_config_form(%{node: %{type: "sink"}} = assigns), do: ~H"<.sink_config node={@node} />"
  defp node_config_form(assigns), do: ~H"<.empty_config_state />"

  # ── Source node configuration ─────────────────────────────────────

  defp source_config(assigns) do
    source_config = assigns.node.data["sourceConfig"] || %{}
    source_type = source_config["type"] || "queue"

    assigns =
      assigns
      |> assign(:source_config, source_config)
      |> assign(:source_type, source_type)

    ~H"""
    <form phx-change="update_node_config" phx-submit="update_node_config">
      <div class="space-y-4">
        <div class="flex items-center gap-3 pb-3 border-b border-base-200">
          <div class="p-2 bg-primary/10 rounded-lg text-primary">
            <.icon name={source_icon(@source_type)} class="w-5 h-5" />
          </div>
          <div>
            <p class="font-semibold text-sm">{@node.data["label"] || "Source"}</p>
            <p class="text-xs text-base-content/50">Source Node</p>
          </div>
        </div>

        <div class="form-control">
          <.field_label text="Label" tooltip="Display name shown on the canvas node" />
          <input
            type="text"
            name="label"
            value={@node.data["label"] || "Source"}
            placeholder="Source"
            class="input input-bordered input-sm w-full"
          />
        </div>

        <div class="form-control">
          <.field_label text="Source Type" tooltip="How this pipeline receives incoming data" />
          <select
            name="source_type"
            phx-change="update_source_type"
            class="select select-bordered select-sm w-full"
          >
            <option value="queue" selected={@source_type == "queue"}>Queue Consumer</option>
            <option value="webhook" selected={@source_type == "webhook"}>Webhook Receiver</option>
            <option value="scheduled_poll" selected={@source_type == "scheduled_poll"}>
              Scheduled Poll
            </option>
          </select>
        </div>

        <div class="divider my-1"></div>

        <%= case @source_type do %>
          <% "queue" -> %>
            <.queue_source_config config={@source_config} />
          <% "webhook" -> %>
            <.webhook_source_config config={@source_config} />
          <% "scheduled_poll" -> %>
            <.scheduled_poll_source_config config={@source_config} />
          <% _ -> %>
            <.queue_source_config config={@source_config} />
        <% end %>
      </div>
    </form>
    """
  end

  defp source_icon("webhook"), do: "hero-code-bracket-square"
  defp source_icon("scheduled_poll"), do: "hero-clock"
  defp source_icon(_), do: "hero-arrow-down-tray"

  defp queue_source_config(assigns) do
    ~H"""
    <div class="space-y-3">
      <div class="form-control">
        <.field_label text="Queue Name" tooltip="The RabbitMQ queue to consume messages from" />
        <input
          type="text"
          name="sourceConfig[queue]"
          value={@config["queue"] || ""}
          placeholder="events.incoming"
          class="input input-bordered input-sm w-full"
        />
      </div>

      <div class="form-control">
        <.field_label
          text="Prefetch Count"
          tooltip="Number of messages to prefetch from the queue. Higher values increase throughput but use more memory."
        />
        <input
          type="number"
          name="sourceConfig[prefetchCount]"
          value={@config["prefetchCount"] || 10}
          min="1"
          max="1000"
          class="input input-bordered input-sm w-full"
        />
      </div>

      <div class="form-control">
        <.field_label
          text="Ack Mode"
          tooltip="Auto acknowledges after processing. Manual requires explicit ack in your script."
        />
        <select
          name="sourceConfig[ackMode]"
          class="select select-bordered select-sm w-full"
        >
          <option value="auto" selected={@config["ackMode"] == "auto"}>
            Auto (ack after processing)
          </option>
          <option value="manual" selected={@config["ackMode"] == "manual"}>
            Manual (explicit ack)
          </option>
        </select>
      </div>
    </div>
    """
  end

  defp webhook_source_config(assigns) do
    ~H"""
    <div class="space-y-3">
      <div class="form-control">
        <.field_label text="Webhook Path" tooltip="Endpoint path for receiving webhook data" />
        <input
          type="text"
          name="sourceConfig[webhookPath]"
          value={@config["webhookPath"] || ""}
          placeholder="/webhooks/my-pipeline"
          class="input input-bordered input-sm w-full font-mono"
        />
      </div>

      <div class="form-control">
        <.field_label
          text="Authentication"
          tooltip="Method used to verify incoming webhook requests"
        />
        <select
          name="sourceConfig[authMethod]"
          class="select select-bordered select-sm w-full"
        >
          <option value="none" selected={@config["authMethod"] == "none"}>None (public)</option>
          <option value="bearer" selected={@config["authMethod"] == "bearer"}>Bearer Token</option>
          <option value="basic" selected={@config["authMethod"] == "basic"}>Basic Auth</option>
        </select>
      </div>

      <div class="form-control">
        <.field_label
          text="Content Types"
          tooltip="Comma-separated list of accepted MIME types (e.g. application/json)"
        />
        <input
          type="text"
          name="sourceConfig[allowedContentTypes]"
          value={format_content_types(@config["allowedContentTypes"])}
          placeholder="application/json, application/xml"
          class="input input-bordered input-sm w-full"
        />
      </div>
    </div>
    """
  end

  defp scheduled_poll_source_config(assigns) do
    ~H"""
    <div class="space-y-3">
      <div class="form-control">
        <.field_label text="Poll URL" tooltip="The HTTP endpoint to poll for new data" />
        <input
          type="url"
          name="sourceConfig[pollUrl]"
          value={@config["pollUrl"] || ""}
          placeholder="https://api.example.com/events"
          class="input input-bordered input-sm w-full font-mono"
        />
      </div>

      <div class="form-control">
        <.field_label
          text="Poll Interval"
          tooltip="How often to poll the endpoint, in seconds (10s to 24h)"
        />
        <input
          type="number"
          name="sourceConfig[pollInterval]"
          value={@config["pollInterval"] || 60}
          min="10"
          max="86400"
          class="input input-bordered input-sm w-full"
        />
      </div>

      <div class="form-control">
        <.field_label text="HTTP Method" tooltip="HTTP method used for poll requests" />
        <select
          name="sourceConfig[pollMethod]"
          class="select select-bordered select-sm w-full"
        >
          <option value="GET" selected={@config["pollMethod"] == "GET"}>GET</option>
          <option value="POST" selected={@config["pollMethod"] == "POST"}>POST</option>
        </select>
      </div>

      <div class="form-control">
        <.field_label
          text="Custom Headers"
          tooltip="JSON object of HTTP headers to include with each poll request"
        />
        <textarea
          name="sourceConfig[pollHeaders]"
          placeholder='{"Authorization": "Bearer token"}'
          class="textarea textarea-bordered w-full min-h-20 font-mono text-sm"
        >{format_poll_headers(@config["pollHeaders"])}</textarea>
      </div>
    </div>
    """
  end

  defp format_content_types(nil), do: ""
  defp format_content_types(types) when is_list(types), do: Enum.join(types, ", ")
  defp format_content_types(types), do: to_string(types)

  defp format_poll_headers(nil), do: ""
  defp format_poll_headers(headers) when is_map(headers), do: Jason.encode!(headers, pretty: true)
  defp format_poll_headers(headers), do: to_string(headers)

  # ── Sink node configuration ──────────────────────────────────────

  defp sink_config(assigns) do
    sink_type = assigns.node.data["sinkType"] || "queue"
    assigns = assign(assigns, :sink_type, sink_type)

    ~H"""
    <form phx-change="update_node_config" phx-submit="update_node_config">
      <div class="space-y-4">
        <div class="flex items-center gap-3 pb-3 border-b border-base-200">
          <div class="p-2 bg-secondary/10 rounded-lg text-secondary">
            <.icon name={sink_icon(@sink_type)} class="w-5 h-5" />
          </div>
          <div>
            <p class="font-semibold text-sm">{@node.data["label"] || "Output"}</p>
            <p class="text-xs text-base-content/50">Output Node</p>
          </div>
        </div>

        <div class="form-control">
          <.field_label text="Label" tooltip="Display name shown on the canvas node" />
          <input
            type="text"
            name="label"
            value={@node.data["label"] || default_sink_label(@sink_type)}
            placeholder={default_sink_label(@sink_type)}
            class="input input-bordered input-sm w-full"
          />
        </div>

        <%= if @sink_type == "queue" do %>
          <div class="form-control">
            <.field_label
              text="Queue Name"
              tooltip="The RabbitMQ queue to publish processed messages to"
            />
            <input
              type="text"
              name="queue"
              value={@node.data["queue"] || ""}
              placeholder="events.processed"
              class="input input-bordered input-sm w-full"
            />
          </div>
        <% else %>
          <div class="form-control">
            <.field_label text="Sink Type" />
            <div class="badge badge-secondary">{String.upcase(@sink_type)}</div>
          </div>

          <div class="form-control">
            <.field_label
              text="Sink Name"
              tooltip="Configure this sink's connection details on the Sinks page"
            />
            <p class="text-sm">{@node.data["sinkName"] || "Unknown"}</p>
          </div>
        <% end %>
      </div>
    </form>
    """
  end

  defp sink_icon("http"), do: "hero-globe-alt"
  defp sink_icon("s3"), do: "hero-cloud-arrow-up"
  defp sink_icon("postgres"), do: "hero-circle-stack"
  defp sink_icon(_), do: "hero-queue-list"

  defp default_sink_label("queue"), do: "Queue Output"
  defp default_sink_label(_), do: "Output"

  # ── Step node configuration ──────────────────────────────────────

  defp step_config(assigns) do
    step_type = assigns.node.data["stepType"]
    assigns = assign(assigns, :step_type, step_type)

    ~H"""
    <form phx-change="update_node_config" phx-submit="update_node_config">
      <div class="space-y-4">
        <div class="flex items-center gap-3 pb-3 border-b border-base-200">
          <div class="p-2 bg-accent/10 rounded-lg text-accent">
            <.icon name={step_icon(@step_type)} class="w-5 h-5" />
          </div>
          <div>
            <p class="font-semibold text-sm">{@node.data["label"] || "Step"}</p>
            <p class="text-xs text-base-content/50">{step_type_label(@step_type)} Step</p>
          </div>
        </div>

        <div class="form-control">
          <.field_label text="Label" tooltip="Display name shown on the canvas node" />
          <input
            type="text"
            name="label"
            value={@node.data["label"] || default_step_label(@step_type)}
            placeholder={default_step_label(@step_type)}
            class="input input-bordered input-sm w-full"
          />
        </div>

        <div class="divider my-1"></div>

        <%= case @step_type do %>
          <% "filter" -> %>
            <.filter_config node={@node} />
          <% "map" -> %>
            <.map_config node={@node} />
          <% "rename" -> %>
            <.rename_config node={@node} />
          <% "script" -> %>
            <.script_config node={@node} />
          <% "anomaly" -> %>
            <.anomaly_config node={@node} advanced_ai={@advanced_ai} />
          <% _ -> %>
            <p class="text-sm text-base-content/60">Unknown step type</p>
        <% end %>
      </div>
    </form>
    """
  end

  defp step_icon("filter"), do: "hero-funnel"
  defp step_icon("map"), do: "hero-arrow-path"
  defp step_icon("rename"), do: "hero-pencil"
  defp step_icon("script"), do: "hero-code-bracket"
  defp step_icon("anomaly"), do: "hero-cpu-chip"
  defp step_icon(_), do: "hero-cog-6-tooth"

  defp default_step_label("filter"), do: "Filter"
  defp default_step_label("map"), do: "Transform"
  defp default_step_label("rename"), do: "Rename"
  defp default_step_label("script"), do: "Script"
  defp default_step_label("anomaly"), do: "AI Detect"
  defp default_step_label(_), do: "Step"

  defp step_type_label("filter"), do: "Filter"
  defp step_type_label("map"), do: "Transform"
  defp step_type_label("rename"), do: "Rename"
  defp step_type_label("script"), do: "Script"
  defp step_type_label("anomaly"), do: "AI Detection"
  defp step_type_label(_), do: "Processing"

  # Filter step configuration
  defp filter_config(assigns) do
    config = assigns.node.data["config"] || %{}
    operator = config["operator"] || "eq"
    assigns = assign(assigns, :config, config) |> assign(:operator, operator)

    ~H"""
    <div class="space-y-3">
      <div class="form-control">
        <.field_label
          text="Field"
          tooltip="Dot-notation path to the field to filter on (e.g. data.status)"
        />
        <input
          type="text"
          name="config[field]"
          value={@config["field"] || ""}
          placeholder="data.status"
          class="input input-bordered input-sm w-full"
        />
      </div>

      <div class="form-control">
        <.field_label text="Operator" tooltip="Comparison operator to apply against the field value" />
        <select
          name="config[operator]"
          class="select select-bordered select-sm w-full"
        >
          <option value="eq" selected={@operator == "eq"}>Equals</option>
          <option value="ne" selected={@operator == "ne"}>Not Equals</option>
          <option value="in" selected={@operator == "in"}>In List</option>
          <option value="not_in" selected={@operator == "not_in"}>Not In List</option>
          <option value="gt" selected={@operator == "gt"}>Greater Than</option>
          <option value="gte" selected={@operator == "gte"}>Greater Or Equal</option>
          <option value="lt" selected={@operator == "lt"}>Less Than</option>
          <option value="lte" selected={@operator == "lte"}>Less Or Equal</option>
          <option value="contains" selected={@operator == "contains"}>Contains</option>
          <option value="matches" selected={@operator == "matches"}>Matches Regex</option>
        </select>
      </div>

      <%= if @operator in ["in", "not_in"] do %>
        <div class="form-control">
          <.field_label text="Values" tooltip="Comma-separated list of values to match against" />
          <input
            type="text"
            name="config[values]"
            value={format_values(@config["values"])}
            placeholder="value1, value2, value3"
            class="input input-bordered input-sm w-full"
          />
        </div>
      <% else %>
        <div class="form-control">
          <.field_label text="Value" tooltip="The value to compare the field against" />
          <input
            type="text"
            name="config[value]"
            value={@config["value"] || ""}
            placeholder="expected value"
            class="input input-bordered input-sm w-full"
          />
        </div>
      <% end %>
    </div>
    """
  end

  defp format_values(nil), do: ""
  defp format_values(values) when is_list(values), do: Enum.join(values, ", ")
  defp format_values(values), do: to_string(values)

  # Map step configuration
  defp map_config(assigns) do
    config = assigns.node.data["config"] || %{}
    assigns = assign(assigns, :config, config)

    ~H"""
    <div class="space-y-3">
      <div class="form-control">
        <.field_label
          text="Source Field"
          tooltip="Dot-notation path to read from (e.g. data.user.email)"
        />
        <input
          type="text"
          name="config[field]"
          value={@config["field"] || ""}
          placeholder="data.user.email"
          class="input input-bordered input-sm w-full"
        />
      </div>

      <div class="form-control">
        <.field_label text="Target Field" tooltip="Field name to write the value to in the output" />
        <input
          type="text"
          name="config[to]"
          value={@config["to"] || ""}
          placeholder="email"
          class="input input-bordered input-sm w-full"
        />
      </div>

      <div class="form-control">
        <.field_label
          text="Default Value"
          tooltip="Fallback value when the source field is missing or null"
        />
        <input
          type="text"
          name="config[default]"
          value={@config["default"] || ""}
          placeholder="Leave empty for no default"
          class="input input-bordered input-sm w-full"
        />
      </div>
    </div>
    """
  end

  # Rename step configuration
  defp rename_config(assigns) do
    config = assigns.node.data["config"] || %{}
    assigns = assign(assigns, :config, config)

    ~H"""
    <div class="space-y-3">
      <div class="form-control">
        <.field_label text="From" tooltip="Current field name to rename" />
        <input
          type="text"
          name="config[from]"
          value={@config["from"] || ""}
          placeholder="old_field_name"
          class="input input-bordered input-sm w-full"
        />
      </div>

      <div class="form-control">
        <.field_label text="To" tooltip="New name for the field" />
        <input
          type="text"
          name="config[to]"
          value={@config["to"] || ""}
          placeholder="new_field_name"
          class="input input-bordered input-sm w-full"
        />
      </div>
    </div>
    """
  end

  # Script step configuration
  defp script_config(assigns) do
    config = assigns.node.data["config"] || %{}
    assigns = assign(assigns, :config, config)

    ~H"""
    <div class="space-y-3">
      <div class="form-control">
        <.field_label
          text="Lua Script"
          tooltip="Custom Lua function that transforms each message. Must return the modified data."
        />
        <textarea
          name="config[code]"
          placeholder="function transform(data)\n  return data\nend"
          class="textarea textarea-bordered w-full min-h-32 font-mono text-sm"
        >{@config["code"] || ""}</textarea>
      </div>

      <div class="form-control">
        <.field_label
          text="Timeout"
          tooltip="Maximum execution time per message in milliseconds (100ms to 30s)"
        />
        <input
          type="number"
          name="config[timeout_ms]"
          value={@config["timeout_ms"] || 5000}
          min="100"
          max="30000"
          class="input input-bordered input-sm w-full"
        />
      </div>
    </div>
    """
  end

  # Anomaly detection step configuration
  defp anomaly_config(assigns) do
    config = assigns.node.data["config"] || %{}
    mode = config["mode"] || "numeric"

    assigns =
      assigns
      |> assign(:config, config)
      |> assign(:mode, mode)

    ~H"""
    <div class="space-y-3">
      <div class="form-control">
        <.field_label
          text="Detection Mode"
          tooltip="How anomalies are scored. Advanced modes (seasonal, multivariate, categorical) are a Pro feature."
        />
        <select
          name="config[mode]"
          disabled={!@advanced_ai}
          class="select select-bordered select-sm w-full"
        >
          <option value="numeric" selected={@mode == "numeric"}>Numeric — rolling z-score</option>
          <option value="seasonal" selected={@mode == "seasonal"} disabled={!@advanced_ai}>
            Seasonal — cycle-aware {pro_suffix(@advanced_ai)}
          </option>
          <option value="multivariate" selected={@mode == "multivariate"} disabled={!@advanced_ai}>
            Multivariate — joint outliers {pro_suffix(@advanced_ai)}
          </option>
          <option value="categorical" selected={@mode == "categorical"} disabled={!@advanced_ai}>
            Categorical — rare-value {pro_suffix(@advanced_ai)}
          </option>
        </select>
        <p :if={!@advanced_ai} class="text-xs text-base-content/50 mt-1">
          Advanced detection modes require a Pro license.
        </p>
      </div>

      <div class="form-control">
        <.field_label
          text="Fields to Monitor"
          tooltip="Comma-separated fields to analyze. Multivariate scores them jointly as one feature vector; the others score each field independently."
        />
        <input
          type="text"
          name="config[fields]"
          value={format_values(@config["fields"])}
          placeholder={fields_placeholder(@mode)}
          class="input input-bordered input-sm w-full"
        />
      </div>

      <%!-- Mode-specific parameters (Pro) --%>
      <div :if={@advanced_ai and @mode == "seasonal"} class="form-control">
        <.field_label
          text="Seasonal Period"
          tooltip="Number of samples in one full cycle (e.g. 7 for daily samples with a weekly cycle, 24 for hourly with a daily cycle)."
        />
        <input
          type="number"
          name="config[period]"
          value={@config["period"] || 7}
          min="2"
          step="1"
          class="input input-bordered input-sm w-full"
        />
      </div>

      <div :if={@advanced_ai and @mode == "categorical"} class="form-control">
        <.field_label
          text="Smoothing (α)"
          tooltip="Smoothing constant. Higher values are more forgiving of unseen values."
        />
        <input
          type="number"
          name="config[smoothing]"
          value={@config["smoothing"] || 1.0}
          min="0.01"
          step="0.1"
          class="input input-bordered input-sm w-full"
        />
      </div>

      <div :if={@advanced_ai and @mode == "multivariate"} class="grid grid-cols-2 gap-2">
        <div class="form-control">
          <.field_label text="Trees" tooltip="Number of trees in the detection ensemble." />
          <input
            type="number"
            name="config[n_trees]"
            value={@config["n_trees"] || 100}
            min="10"
            step="10"
            class="input input-bordered input-sm w-full"
          />
        </div>
        <div class="form-control">
          <.field_label text="Subsample" tooltip="Vectors sampled per tree when fitting." />
          <input
            type="number"
            name="config[subsample]"
            value={@config["subsample"] || 256}
            min="16"
            step="16"
            class="input input-bordered input-sm w-full"
          />
        </div>
      </div>

      <div class="form-control">
        <.field_label
          text="Threshold"
          tooltip={threshold_tooltip(@mode)}
        />
        <input
          type="number"
          name="config[threshold]"
          value={@config["threshold"] || default_threshold(@mode)}
          step="0.05"
          min="0"
          max="10"
          class="input input-bordered input-sm w-full"
        />
      </div>
    </div>
    """
  end

  defp pro_suffix(true), do: ""
  defp pro_suffix(false), do: "(Pro)"

  defp fields_placeholder("categorical"), do: "country, plan_tier"
  defp fields_placeholder("multivariate"), do: "amount, lat, lng"
  defp fields_placeholder(_), do: "cpu_usage, memory, latency"

  defp default_threshold("seasonal"), do: 3.0
  defp default_threshold("multivariate"), do: 0.65
  defp default_threshold("categorical"), do: 4.0
  defp default_threshold(_), do: 2.0

  defp threshold_tooltip("multivariate"),
    do: "Anomaly score in 0–1; values above this are flagged (≈0.6–0.7 is typical)."

  defp threshold_tooltip("categorical"),
    do: "Rarity score in bits; rarer values score higher. Above this is flagged."

  defp threshold_tooltip(_),
    do: "Standard deviations from the (de-seasonalized) mean. Beyond this is flagged."

  # ── Edge configuration ────────────────────────────────────────────

  defp edge_config_form(assigns) do
    source_label = get_node_label(assigns.ir, assigns.edge[:source])
    target_label = get_node_label(assigns.ir, assigns.edge[:target])

    assigns =
      assigns
      |> assign(:source_label, source_label)
      |> assign(:target_label, target_label)

    ~H"""
    <form phx-change="update_edge_config" phx-submit="update_edge_config">
      <div class="space-y-4">
        <div class="flex items-center gap-3 pb-3 border-b border-base-200">
          <div class="p-2 bg-base-content/10 rounded-lg text-base-content">
            <.icon name="hero-arrow-long-right" class="w-5 h-5" />
          </div>
          <div>
            <p class="font-semibold text-sm">Edge</p>
            <p class="text-xs text-base-content/50">Connection</p>
          </div>
        </div>

        <div class="form-control">
          <.field_label text="Connection" />
          <div class="flex items-center gap-2 text-xs">
            <span class="font-mono bg-base-200 px-2 py-1 rounded truncate max-w-[100px]">
              {@source_label}
            </span>
            <.icon name="hero-arrow-right" class="w-3.5 h-3.5 text-base-content/40 shrink-0" />
            <span class="font-mono bg-base-200 px-2 py-1 rounded truncate max-w-[100px]">
              {@target_label}
            </span>
          </div>
        </div>

        <div class="form-control">
          <.field_label text="Label" tooltip="Optional text displayed on the edge in the canvas" />
          <input
            type="text"
            name="edge_label"
            value={@edge[:label] || ""}
            placeholder="Describe this connection"
            class="input input-bordered input-sm w-full"
          />
        </div>
      </div>
    </form>
    """
  end

  defp get_node_label(ir, node_id) when is_binary(node_id) do
    # Check nodes array first
    case ir["nodes"] do
      nodes when is_list(nodes) ->
        case Enum.find(nodes, fn n -> n["id"] == node_id end) do
          %{"label" => label} -> label
          _ -> fallback_label(ir, node_id)
        end

      _ ->
        fallback_label(ir, node_id)
    end
  end

  defp get_node_label(_ir, _node_id), do: "?"

  defp fallback_label(ir, node_id) do
    cond do
      node_id == "source" ->
        "Source"

      node_id == "output" ->
        "Output"

      true ->
        case ir["steps"] do
          steps when is_list(steps) ->
            case Enum.find(steps, fn s -> s["id"] == node_id end) do
              %{"operation" => op} -> String.capitalize(op)
              _ -> node_id
            end

          _ ->
            node_id
        end
    end
  end

  # ── Event handlers ───────────────────────────────────────────────

  @impl true
  def handle_event("update_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, :pipeline_name, name)}
  end

  def handle_event("save", _params, socket) do
    permission = if socket.assigns.action == :new, do: :create_pipeline, else: :edit_pipeline

    authorize(socket, permission, fn ->
      # Extract source_queue from the IR for backward compat with the schema
      source_queue = extract_source_queue(socket.assigns.initial_ir)
      was_new = socket.assigns.action == :new

      sink_ids = extract_sink_ids(socket.assigns.initial_ir)

      attrs = %{
        name: socket.assigns.pipeline_name,
        source_queue: source_queue || "default",
        steps: socket.assigns.initial_ir,
        sink_ids: sink_ids,
        organization_id: socket.assigns.current_scope.organization_id
      }

      result =
        case socket.assigns.action do
          :new -> Pipelines.create_pipeline(attrs)
          :edit -> Pipelines.update_pipeline(socket.assigns.pipeline, attrs)
        end

      case result do
        {:ok, pipeline} ->
          socket =
            socket
            |> assign(:pipeline, pipeline)
            |> assign(:action, :edit)
            |> put_flash(:info, "Pipeline saved")

          # Navigate to the edit URL so refreshing doesn't re-create
          if was_new do
            {:noreply, push_patch(socket, to: ~p"/pipelines/#{pipeline.id}/builder")}
          else
            {:noreply, socket}
          end

        {:error, changeset} ->
          {:noreply, put_flash(socket, :error, format_save_errors(changeset))}
      end
    end)
  end

  def handle_event("update_ir", %{"ir" => ir_json}, socket) do
    case Jason.decode(ir_json) do
      {:ok, ir} ->
        {:noreply, assign(socket, :initial_ir, ir)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Invalid pipeline configuration")}
    end
  end

  # Handle node selection from React Flow
  def handle_event(
        "select_node",
        %{"nodeId" => node_id, "nodeType" => node_type, "nodeData" => node_data},
        socket
      ) do
    selected_node = %{
      id: node_id,
      type: node_type,
      data: node_data
    }

    {:noreply,
     socket
     |> assign(:selected_node, selected_node)
     |> assign(:selected_edge, nil)}
  end

  # Handle edge selection with data
  def handle_event(
        "select_node",
        %{"edgeId" => edge_id, "edgeData" => edge_data},
        socket
      ) do
    selected_edge = %{
      id: edge_id,
      source: edge_data["source"],
      target: edge_data["target"],
      label: edge_data["label"]
    }

    {:noreply,
     socket
     |> assign(:selected_node, nil)
     |> assign(:selected_edge, selected_edge)}
  end

  # Handle edge selection without data (backward compat)
  def handle_event("select_node", %{"edgeId" => edge_id}, socket) do
    {:noreply,
     socket
     |> assign(:selected_node, nil)
     |> assign(:selected_edge, %{id: edge_id})}
  end

  # Handle deselection (empty selection)
  def handle_event("select_node", %{}, socket) do
    {:noreply,
     socket
     |> assign(:selected_node, nil)
     |> assign(:selected_edge, nil)}
  end

  # Handle source type change
  def handle_event("update_source_type", %{"source_type" => type}, socket) do
    node = socket.assigns.selected_node

    if node && node.type == "source" do
      existing_config = Map.get(node.data, "sourceConfig", %{})
      updated_config = Map.put(existing_config, "type", type)
      updated_data = Map.put(node.data, "sourceConfig", updated_config)

      socket =
        push_event(socket, "update_node_data", %{
          nodeId: node.id,
          data: updated_data
        })

      {:noreply, assign(socket, :selected_node, %{node | data: updated_data})}
    else
      {:noreply, socket}
    end
  end

  # Handle edge config updates
  def handle_event("update_edge_config", %{"edge_label" => label}, socket) do
    edge = socket.assigns.selected_edge

    if edge do
      updated_edge = Map.put(edge, :label, label)

      socket =
        push_event(socket, "update_edge_label", %{
          edgeId: edge.id,
          label: label
        })

      {:noreply, assign(socket, :selected_edge, updated_edge)}
    else
      {:noreply, socket}
    end
  end

  # Handle node config updates from the form
  def handle_event("update_node_config", params, socket) do
    node = socket.assigns.selected_node

    if node do
      updated_data = update_node_data_from_params(node.data, params)

      socket =
        push_event(socket, "update_node_data", %{
          nodeId: node.id,
          data: updated_data
        })

      {:noreply, assign(socket, :selected_node, %{node | data: updated_data})}
    else
      {:noreply, socket}
    end
  end

  defp update_node_data_from_params(data, params) do
    # With phx-change on a form, _target tells us which field changed.
    # We use _target to determine what to update from the params.
    target = params["_target"]

    case target do
      # Nested field like ["sourceConfig", "queue"] or ["config", "field"]
      [parent, child] when is_binary(parent) and is_binary(child) ->
        value = get_in(params, [parent, child])
        existing = Map.get(data, parent, %{})
        Map.put(data, parent, Map.put(existing, child, value))

      # Top-level field like ["label"] or ["queue"]
      [field] when is_binary(field) ->
        case Map.get(params, field) do
          nil -> data
          value -> Map.put(data, field, value)
        end

      # No _target (legacy phx-blur fallback)
      nil ->
        update_node_data_legacy(data, params)

      _ ->
        data
    end
  end

  # Fallback for any remaining non-form event params
  defp update_node_data_legacy(data, params) do
    cond do
      Map.has_key?(params, "config") ->
        existing_config = Map.get(data, "config", %{})
        Map.put(data, "config", Map.merge(existing_config, params["config"]))

      Map.has_key?(params, "sourceConfig") ->
        existing_source = Map.get(data, "sourceConfig", %{})
        Map.put(data, "sourceConfig", Map.merge(existing_source, params["sourceConfig"]))

      Map.has_key?(params, "label") ->
        Map.put(data, "label", params["label"])

      Map.has_key?(params, "queue") ->
        Map.put(data, "queue", params["queue"])

      true ->
        data
    end
  end

  defp format_save_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join(", ", fn {field, errors} ->
      "#{Phoenix.Naming.humanize(field)} #{Enum.join(errors, ", ")}"
    end)
  end

  defp extract_sink_ids(ir) do
    case ir["nodes"] do
      nodes when is_list(nodes) ->
        for n <- nodes, n["type"] == "sink", sink_id = n["sinkId"], sink_id != nil, uniq: true do
          to_integer(sink_id)
        end

      _ ->
        []
    end
  end

  defp to_integer(val) when is_integer(val), do: val
  defp to_integer(val) when is_binary(val), do: String.to_integer(val)

  defp extract_source_queue(ir) do
    case ir["nodes"] do
      nodes when is_list(nodes) ->
        case Enum.find(nodes, fn n -> n["type"] == "source" end) do
          %{"sourceConfig" => %{"queue" => queue}} when is_binary(queue) and queue != "" ->
            queue

          _ ->
            nil
        end

      _ ->
        nil
    end
  end
end
