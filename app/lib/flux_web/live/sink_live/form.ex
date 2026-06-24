defmodule FluxWeb.SinkLive.Form do
  @moduledoc "LiveView for creating and editing sink configurations."
  use FluxWeb, :live_view

  import FluxWeb.Authorization

  alias Flux.Sinks
  alias Flux.Sinks.Sink
  alias FluxWeb.Components.UpgradePrompt

  # Sink types gated behind a Pro/EE license, mapped to their entitlement feature.
  @pro_sink_features %{"s3" => :s3_sink}

  @impl true
  def mount(params, _session, socket) do
    {sink, action, title} =
      case params do
        %{"id" => id} ->
          sink = Sinks.get_sink(id, socket.assigns.current_scope.organization_id)
          {sink || %Sink{}, :edit, "Edit Sink"}

        _ ->
          {%Sink{type: "http", config: %{}}, :new, "New Sink"}
      end

    changeset = Sinks.change_sink(sink)

    {:ok,
     socket
     |> assign(:active_tab, :sinks)
     |> assign(:page_title, title)
     |> assign(:action, action)
     |> assign(:sink, sink)
     |> assign(:form, to_form(changeset))
     |> assign(:selected_type, sink.type || "http")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto">
      <div class="flex items-center gap-4 mb-6">
        <.link navigate={~p"/sinks"} class="btn btn-ghost btn-sm">
          <.icon name="hero-arrow-left" class="w-4 h-4" />
        </.link>
        <h1 class="text-2xl font-bold tracking-tight text-base-content">
          {@page_title}
        </h1>
      </div>

      <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-6">
        <div class="card bg-base-100 shadow-sm border border-base-200">
          <div class="card-body">
            <h2 class="card-title text-base mb-4">Basic Information</h2>

            <div class="form-control">
              <.input field={@form[:name]} type="text" label="Name" placeholder="My Webhook Sink" />
            </div>

            <div class="form-control mt-4">
              <.input
                field={@form[:description]}
                type="textarea"
                label="Description"
                placeholder="Optional description..."
              />
            </div>

            <div class="form-control mt-4">
              <label class="label">
                <span class="label-text font-medium">Sink Type</span>
              </label>
              <div class="grid grid-cols-2 gap-3">
                <.sink_type_option
                  field={@form[:type]}
                  selected_type={@selected_type}
                  type="http"
                  icon="hero-globe-alt"
                  label="HTTP"
                  sublabel="Webhook"
                />
                <.sink_type_option
                  field={@form[:type]}
                  selected_type={@selected_type}
                  type="s3"
                  icon="hero-cloud-arrow-up"
                  label="S3"
                  sublabel="Object Storage"
                />
                <.sink_type_option
                  field={@form[:type]}
                  selected_type={@selected_type}
                  type="postgres"
                  icon="hero-circle-stack"
                  label="Postgres"
                  sublabel="Database"
                />
                <.sink_type_option
                  field={@form[:type]}
                  selected_type={@selected_type}
                  type="mysql"
                  icon="hero-circle-stack"
                  label="MySQL"
                  sublabel="Database"
                />
              </div>
            </div>
          </div>
        </div>

        <div class="card bg-base-100 shadow-sm border border-base-200">
          <div class="card-body">
            <h2 class="card-title text-base mb-4">Configuration</h2>
            <div :if={pro_locked?(@selected_type)}>
              <UpgradePrompt.upgrade_prompt feature={pro_feature(@selected_type)} />
            </div>
            <.type_config_fields
              :if={!pro_locked?(@selected_type)}
              type={@selected_type}
              form={@form}
            />
          </div>
        </div>

        <div class="flex justify-end gap-3">
          <.link navigate={~p"/sinks"} class="btn btn-ghost">Cancel</.link>
          <button type="submit" class="btn btn-primary">
            <.icon name="hero-check" class="w-5 h-5" />
            {if @action == :new, do: "Create Sink", else: "Update Sink"}
          </button>
        </div>
      </.form>
    </div>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :selected_type, :string, required: true
  attr :type, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :sublabel, :string, required: true

  # One selectable tile in the sink-type picker. The hidden radio keeps the
  # selection in the form while `select_type` drives the highlighted state.
  defp sink_type_option(assigns) do
    ~H"""
    <label class={[
      "cursor-pointer border-2 rounded-lg p-4 text-center transition-all",
      @selected_type == @type && "border-primary bg-primary/5",
      @selected_type != @type && "border-base-300 hover:border-primary/50"
    ]}>
      <input
        type="radio"
        name={@field.name}
        value={@type}
        checked={@selected_type == @type}
        class="hidden"
        phx-click="select_type"
        phx-value-type={@type}
      />
      <.icon name={@icon} class="w-8 h-8 mx-auto text-primary" />
      <p class="font-medium mt-2">{@label}</p>
      <p class="text-xs text-base-content/60">{@sublabel}</p>
    </label>
    """
  end

  defp type_config_fields(%{type: "http"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.input
        field={@form[:config_url]}
        type="url"
        label="Webhook URL"
        placeholder="https://example.com/webhook"
      />
      <.input
        field={@form[:config_method]}
        type="select"
        label="HTTP Method"
        options={["POST", "PUT", "PATCH"]}
      />
      <.input field={@form[:config_timeout]} type="number" label="Timeout (ms)" placeholder="30000" />
    </div>
    """
  end

  defp type_config_fields(%{type: "s3"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.input field={@form[:config_bucket]} type="text" label="Bucket Name" placeholder="my-bucket" />
      <.input
        field={@form[:config_key_template]}
        type="text"
        label="Key Template"
        placeholder="data/{date}/{id}.json"
      />
      <p class="text-xs text-base-content/60 -mt-2">
        Placeholders: {"{id}"}, {"{timestamp}"}, {"{date}"}, {"{pipeline_id}"}
      </p>
      <.input field={@form[:config_region]} type="text" label="Region" placeholder="us-east-1" />
      <.input
        field={@form[:config_endpoint]}
        type="url"
        label="Custom Endpoint (for MinIO)"
        placeholder="http://minio:9000"
      />
      <.input
        field={@form[:config_access_key]}
        type="text"
        label="Access Key ID"
        placeholder="Optional - uses env if empty"
      />
      <.input
        field={@form[:config_secret_key]}
        type="password"
        label="Secret Access Key"
        placeholder="Optional - uses env if empty"
      />
    </div>
    """
  end

  defp type_config_fields(%{type: "postgres"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.input
        field={@form[:config_mode]}
        type="select"
        label="Mode"
        options={[{"Internal (Flux DB)", "internal"}, {"External Database", "external"}]}
      />
      <.input field={@form[:config_table]} type="text" label="Table Name" placeholder="events" />
      <.input
        field={@form[:config_database_url]}
        type="text"
        label="Database URL (for external)"
        placeholder="postgres://user:pass@host:5432/db"
      />
      <.input
        field={@form[:config_columns]}
        type="textarea"
        label="Column Mapping (JSON)"
        placeholder='{"event_type": "type", "payload.user_id": "user_id"}'
      />
    </div>
    """
  end

  defp type_config_fields(%{type: "mysql"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.input
        field={@form[:config_database_url]}
        type="text"
        label="Database URL"
        placeholder="mysql://user:pass@host:3306/db"
      />
      <p class="text-xs text-base-content/60 -mt-2">
        Flux connects out to this database — make sure its host/port allows the Flux
        server's egress IP. See <code>docs/connectors/external-databases.md</code>.
      </p>
      <.input field={@form[:config_table]} type="text" label="Table Name" placeholder="events" />
      <.input
        field={@form[:config_columns]}
        type="textarea"
        label="Column Mapping (JSON)"
        placeholder={~s({"event_type": "type", "payload.user_id": "user_id"})}
      />
      <.input
        field={@form[:config_on_conflict]}
        type="select"
        label="On Duplicate Key"
        options={[
          {"Raise error", "raise"},
          {"Ignore duplicates", "ignore"},
          {"Update (upsert)", "update"}
        ]}
      />
      <.input field={@form[:config_ssl]} type="checkbox" label="Use TLS/SSL connection" />
    </div>
    """
  end

  defp type_config_fields(assigns) do
    ~H"""
    <p class="text-base-content/60">Select a sink type to configure.</p>
    """
  end

  @impl true
  def handle_event("select_type", %{"type" => type}, socket) do
    {:noreply, assign(socket, :selected_type, type)}
  end

  def handle_event("validate", %{"sink" => params}, socket) do
    params = merge_config_params(params, socket.assigns.selected_type)

    changeset =
      socket.assigns.sink
      |> Sinks.change_sink(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"sink" => params}, socket) do
    permission = if socket.assigns.action == :new, do: :create_sink, else: :edit_sink

    authorize(socket, permission, fn ->
      if pro_locked?(socket.assigns.selected_type) do
        {:noreply,
         put_flash(
           socket,
           :error,
           "#{pro_label(socket.assigns.selected_type)} requires Flux Pro."
         )}
      else
        params = merge_config_params(params, socket.assigns.selected_type)
        params = Map.put(params, "organization_id", socket.assigns.current_scope.organization_id)

        case socket.assigns.action do
          :new -> create_sink(socket, params)
          :edit -> update_sink(socket, params)
        end
      end
    end)
  end

  defp create_sink(socket, params) do
    case Sinks.create_sink(params) do
      {:ok, _sink} ->
        {:noreply,
         socket
         |> put_flash(:info, "Sink created successfully")
         |> push_navigate(to: ~p"/sinks")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp update_sink(socket, params) do
    case Sinks.update_sink(socket.assigns.sink, params) do
      {:ok, _sink} ->
        {:noreply,
         socket
         |> put_flash(:info, "Sink updated successfully")
         |> push_navigate(to: ~p"/sinks")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp merge_config_params(params, type) do
    config = build_config(params, type)

    params
    |> Map.put("type", type)
    |> Map.put("config", config)
  end

  defp build_config(params, "http") do
    %{}
    |> maybe_put("url", params["config_url"])
    |> maybe_put("method", params["config_method"])
    |> maybe_put("timeout_ms", parse_int(params["config_timeout"]))
  end

  defp build_config(params, "s3") do
    %{}
    |> maybe_put("bucket", params["config_bucket"])
    |> maybe_put("key_template", params["config_key_template"])
    |> maybe_put("region", params["config_region"])
    |> maybe_put("endpoint", params["config_endpoint"])
    |> maybe_put("access_key_id", params["config_access_key"])
    |> maybe_put("secret_access_key", params["config_secret_key"])
  end

  defp build_config(params, "postgres") do
    columns =
      case Jason.decode(params["config_columns"] || "{}") do
        {:ok, map} when is_map(map) -> map
        _ -> %{}
      end

    %{}
    |> maybe_put("mode", params["config_mode"])
    |> maybe_put("table", params["config_table"])
    |> maybe_put("database_url", params["config_database_url"])
    |> Map.put("columns", columns)
  end

  defp build_config(params, "mysql") do
    columns =
      case Jason.decode(params["config_columns"] || "{}") do
        {:ok, map} when is_map(map) -> map
        _ -> %{}
      end

    %{}
    |> maybe_put("database_url", params["config_database_url"])
    |> maybe_put("table", params["config_table"])
    |> maybe_put("on_conflict", params["config_on_conflict"])
    |> Map.put("ssl", params["config_ssl"] == "true")
    |> Map.put("columns", columns)
  end

  defp build_config(_params, _type), do: %{}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_int(val), do: val

  # A Pro sink type is "locked" when the current license isn't entitled to it.
  # Community always returns false from entitled?/1, so the upgrade prompt shows;
  # a licensed EE build resolves to true and the config fields render.
  defp pro_locked?(type) do
    case Map.fetch(@pro_sink_features, type) do
      {:ok, feature} -> not Flux.License.entitled?(feature)
      :error -> false
    end
  end

  defp pro_feature(type), do: Map.get(@pro_sink_features, type, :pro_sink)

  defp pro_label("s3"), do: "S3 sinks"
  defp pro_label(type), do: "#{type} sinks"
end
