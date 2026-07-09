defmodule FluxWeb.SinkLive.Form do
  @moduledoc "LiveView for creating and editing sink configurations."
  use FluxWeb, :live_view

  import FluxWeb.Authorization

  alias Flux.Sinks
  alias Flux.Sinks.Sink
  alias FluxWeb.Components.UpgradePrompt

  # Sink types gated behind a Pro/EE license, mapped to their entitlement feature.
  @pro_sink_features %{
    "s3" => :s3_sink,
    "bigquery" => :bigquery_sink,
    "kafka" => :kafka_sink,
    "snowflake" => :snowflake_sink,
    "redis" => :redis_sink,
    "mongodb" => :mongodb_sink
  }

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

    changeset = Sinks.change_sink(sink, config_form_params(sink))

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
    <div class="space-y-6">
      <div class="flex items-center gap-4">
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
              <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
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
                <.sink_type_option
                  field={@form[:type]}
                  selected_type={@selected_type}
                  type="bigquery"
                  icon="hero-table-cells"
                  label="BigQuery"
                  sublabel="Warehouse"
                />
                <.sink_type_option
                  field={@form[:type]}
                  selected_type={@selected_type}
                  type="kafka"
                  icon="hero-queue-list"
                  label="Kafka"
                  sublabel="Event Streaming"
                />
                <.sink_type_option
                  field={@form[:type]}
                  selected_type={@selected_type}
                  type="snowflake"
                  icon="hero-cube"
                  label="Snowflake"
                  sublabel="Warehouse"
                />
                <.sink_type_option
                  field={@form[:type]}
                  selected_type={@selected_type}
                  type="redis"
                  icon="hero-bolt"
                  label="Redis"
                  sublabel="Key-Value Store"
                />
                <.sink_type_option
                  field={@form[:type]}
                  selected_type={@selected_type}
                  type="mongodb"
                  icon="hero-document-text"
                  label="MongoDB"
                  sublabel="Document Store"
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

  defp type_config_fields(%{type: "bigquery"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.input
        field={@form[:config_project_id]}
        type="text"
        label="Project ID"
        placeholder="my-gcp-project"
      />
      <.input field={@form[:config_dataset]} type="text" label="Dataset" placeholder="analytics" />
      <.input field={@form[:config_table]} type="text" label="Table" placeholder="events" />
      <.input
        field={@form[:config_credentials]}
        type="textarea"
        label="Service Account JSON"
        placeholder="Leave blank to use GOOGLE_APPLICATION_CREDENTIALS / Workload Identity"
      />
      <p class="text-xs text-base-content/60 -mt-2">
        Paste a service-account key, or leave blank to fall back to Application Default
        Credentials (e.g. Workload Identity on GKE).
      </p>
      <.input
        field={@form[:config_location]}
        type="text"
        label="Location (optional)"
        placeholder="US"
      />
    </div>
    """
  end

  # Rendered only on a licensed build (Community shows the upgrade prompt instead).
  defp type_config_fields(%{type: "kafka"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.input
        field={@form[:config_bootstrap_servers]}
        type="text"
        label="Bootstrap Servers"
        placeholder="broker1:9092,broker2:9092"
      />
      <.input field={@form[:config_topic]} type="text" label="Topic" placeholder="events" />
      <.input
        field={@form[:config_auth_mode]}
        type="select"
        label="Auth Mode"
        options={[
          {"PLAINTEXT", "plaintext"},
          {"SASL/PLAIN", "sasl_plain"},
          {"SASL/SCRAM-SHA-256", "sasl_scram_256"},
          {"SASL/SCRAM-SHA-512", "sasl_scram_512"},
          {"mTLS", "mtls"}
        ]}
      />
      <.input
        field={@form[:config_sasl_username]}
        type="text"
        label="SASL Username"
        placeholder="Required for SASL auth modes"
      />
      <.input
        field={@form[:config_sasl_password]}
        type="password"
        label="SASL Password"
        placeholder="Required for SASL auth modes"
      />
      <.input
        field={@form[:config_ssl_certfile]}
        type="text"
        label="Client Certificate Path (mTLS)"
        placeholder="/etc/flux/certs/client.pem"
      />
      <.input
        field={@form[:config_ssl_keyfile]}
        type="password"
        label="Client Key Path (mTLS)"
        placeholder="/etc/flux/certs/client.key"
      />
      <.input
        field={@form[:config_compression]}
        type="select"
        label="Compression"
        options={[{"None", "none"}, {"snappy", "snappy"}, {"zstd", "zstd"}, {"lz4", "lz4"}]}
      />
      <.input
        field={@form[:config_transactional]}
        type="checkbox"
        label="Transactional (exactly-once) produce"
      />
    </div>
    """
  end

  # Rendered only on a licensed build (Community shows the upgrade prompt instead).
  defp type_config_fields(%{type: "snowflake"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.input
        field={@form[:config_account]}
        type="text"
        label="Account Identifier"
        placeholder="xy12345.us-east-1"
      />
      <p class="text-xs text-base-content/60 -mt-2">
        Flux egresses to <code>&lt;account&gt;.snowflakecomputing.com</code> over HTTPS
        (443) — make sure the Flux node's outbound/NAT allows it.
      </p>
      <.input field={@form[:config_warehouse]} type="text" label="Warehouse" placeholder="compute_wh" />
      <.input field={@form[:config_database]} type="text" label="Database" placeholder="analytics" />
      <.input field={@form[:config_schema]} type="text" label="Schema" placeholder="public" />
      <.input field={@form[:config_table]} type="text" label="Table" placeholder="events" />
      <.input field={@form[:config_user]} type="text" label="User" placeholder="flux_loader" />
      <.input
        field={@form[:config_private_key]}
        type="password"
        label="Private Key (PEM)"
        placeholder="-----BEGIN PRIVATE KEY-----"
      />
      <.input
        field={@form[:config_private_key_passphrase]}
        type="password"
        label="Private Key Passphrase (optional)"
        placeholder="Only if the key is encrypted"
      />
    </div>
    """
  end

  # Rendered only on a licensed build (Community shows the upgrade prompt instead).
  defp type_config_fields(%{type: "redis"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div class="sm:col-span-2">
          <.input field={@form[:config_host]} type="text" label="Host" placeholder="redis.internal" />
        </div>
        <.input field={@form[:config_port]} type="number" label="Port" placeholder="6379" />
      </div>
      <p class="text-xs text-base-content/60 -mt-2">
        Flux connects out to this Redis server — make sure its host/port allows the
        Flux server's egress IP. See <code>docs/connectors/redis.md</code>.
      </p>
      <.input
        field={@form[:config_db]}
        type="number"
        label="Database (logical DB index)"
        placeholder="0"
      />
      <.input
        field={@form[:config_value_shape]}
        type="select"
        label="Value Shape"
        options={[
          {"String (SET)", "string"},
          {"Hash (HSET)", "hash"},
          {"List (RPUSH)", "list"},
          {"Stream (XADD)", "stream"}
        ]}
      />
      <.input
        field={@form[:config_key_template]}
        type="text"
        label="Key Template"
        placeholder="scores:{id}"
      />
      <p class="text-xs text-base-content/60 -mt-2">
        Placeholders: {"{id}"}, {"{timestamp}"}, {"{date}"}, {"{pipeline_id}"}
      </p>
      <.input
        field={@form[:config_ttl_seconds]}
        type="number"
        label="TTL (seconds, optional)"
        placeholder="Leave blank for no expiry — ignored for streams"
      />
      <.input
        field={@form[:config_auth_mode]}
        type="select"
        label="Auth Mode"
        options={[
          {"None", "none"},
          {"Password (requirepass)", "password"},
          {"ACL (username + password, Redis 6+)", "acl"}
        ]}
      />
      <.input
        field={@form[:config_username]}
        type="text"
        label="Username (ACL)"
        placeholder="Required for ACL auth"
      />
      <.input
        field={@form[:config_password]}
        type="password"
        label="Password"
        placeholder="Required for password / ACL auth"
      />
      <.input field={@form[:config_tls]} type="checkbox" label="Use TLS connection" />
      <.input
        field={@form[:config_cluster]}
        type="checkbox"
        label="Cluster mode (opt-in)"
      />
    </div>
    """
  end

  # Rendered only on a licensed build (Community shows the upgrade prompt instead).
  defp type_config_fields(%{type: "mongodb"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.input
        field={@form[:config_uri]}
        type="text"
        label="Connection URI"
        placeholder="mongodb+srv://user:pass@cluster.mongodb.net"
      />
      <p class="text-xs text-base-content/60 -mt-2">
        A <code>mongodb://</code> or <code>mongodb+srv://</code> URI (covers Atlas, replica
        sets, auth and TLS). Leave blank to use the host/port fields below instead.
      </p>
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div class="sm:col-span-2">
          <.input
            field={@form[:config_host]}
            type="text"
            label="Host (if no URI)"
            placeholder="mongo.internal"
          />
        </div>
        <.input field={@form[:config_port]} type="number" label="Port" placeholder="27017" />
      </div>
      <.input field={@form[:config_database]} type="text" label="Database" placeholder="events" />
      <.input field={@form[:config_collection]} type="text" label="Collection" placeholder="raw" />
      <.input
        field={@form[:config_auth_mode]}
        type="select"
        label="Auth Mode"
        options={[
          {"None", "none"},
          {"SCRAM (username + password)", "scram"},
          {"X.509 client certificate (mTLS)", "x509"}
        ]}
      />
      <.input
        field={@form[:config_username]}
        type="text"
        label="Username (SCRAM)"
        placeholder="Required for SCRAM auth"
      />
      <.input
        field={@form[:config_password]}
        type="password"
        label="Password (SCRAM)"
        placeholder="Required for SCRAM auth"
      />
      <.input
        field={@form[:config_auth_source]}
        type="text"
        label="Auth Source"
        placeholder="admin"
      />
      <.input field={@form[:config_tls]} type="checkbox" label="Use TLS connection" />
      <.input
        field={@form[:config_tls_ca_file]}
        type="text"
        label="TLS CA Certificate Path (optional)"
        placeholder="/etc/flux/certs/ca.pem"
      />
      <.input
        field={@form[:config_tls_cert_file]}
        type="text"
        label="Client Certificate Path (X.509)"
        placeholder="/etc/flux/certs/client.pem"
      />
      <.input
        field={@form[:config_tls_key_file]}
        type="password"
        label="Client Key Path (X.509)"
        placeholder="/etc/flux/certs/client.key"
      />
      <.input
        field={@form[:config_write_mode]}
        type="select"
        label="Write Mode"
        options={[{"Insert", "insert"}, {"Upsert", "upsert"}]}
      />
      <.input
        field={@form[:config_upsert_keys]}
        type="text"
        label="Upsert Keys (for upsert mode)"
        placeholder="Comma-separated fields, e.g. _id or user_id,day"
      />
      <p class="text-xs text-base-content/60 -mt-2">
        Filter fields used to match an existing document. A record's <code>_id</code> is
        preserved when present; otherwise MongoDB generates one.
      </p>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:config_ttl_field]}
          type="text"
          label="TTL Field (optional)"
          placeholder="created_at"
        />
        <.input
          field={@form[:config_ttl_seconds]}
          type="number"
          label="TTL (seconds)"
          placeholder="Expire docs after N seconds"
        />
      </div>
      <p class="text-xs text-base-content/60 -mt-2">
        When both are set, Flux creates a TTL index on the field so MongoDB expires
        documents automatically. The field must hold a date/timestamp.
      </p>
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
    params = merge_config_params(params, socket.assigns.selected_type, socket.assigns.sink)

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
        params = merge_config_params(params, socket.assigns.selected_type, socket.assigns.sink)
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

  # Merge freshly built config over the sink's stored config so that any field
  # the user left blank (dropped by `maybe_put/3` — notably secrets) falls back
  # to the persisted value instead of being silently wiped on edit. When the
  # type changes we start from an empty base so stale keys aren't carried over.
  defp merge_config_params(params, type, sink) do
    built = build_config(params, type)
    base = if type == sink.type, do: sink.config || %{}, else: %{}

    params
    |> Map.put("type", type)
    |> Map.put("config", Map.merge(base, built))
  end

  # Reverse of build_config/2: hydrate the virtual config_* form fields from a
  # sink's stored config on edit so non-secret values render pre-filled. Secret
  # fields are deliberately left blank (a blank secret means "leave unchanged",
  # preserved by merge_config_params/3).
  defp config_form_params(%Sink{config: config, type: type})
       when is_map(config) and map_size(config) > 0 do
    config_form_params(type, config)
  end

  defp config_form_params(_sink), do: %{}

  defp config_form_params("http", config) do
    %{}
    |> put_field("config_url", config["url"])
    |> put_field("config_method", config["method"])
    |> put_field("config_timeout", config["timeout_ms"])
  end

  defp config_form_params("s3", config) do
    # access_key_id / secret_access_key are secret — left blank on edit.
    %{}
    |> put_field("config_bucket", config["bucket"])
    |> put_field("config_key_template", config["key_template"])
    |> put_field("config_region", config["region"])
    |> put_field("config_endpoint", config["endpoint"])
  end

  defp config_form_params("postgres", config) do
    # database_url embeds the password — secret, left blank on edit.
    %{}
    |> put_field("config_mode", config["mode"])
    |> put_field("config_table", config["table"])
    |> put_columns("config_columns", config["columns"])
  end

  defp config_form_params("mysql", config) do
    # database_url embeds the password — secret, left blank on edit.
    %{}
    |> put_field("config_table", config["table"])
    |> put_field("config_on_conflict", config["on_conflict"])
    |> put_field("config_ssl", bool_to_param(config["ssl"]))
    |> put_columns("config_columns", config["columns"])
  end

  defp config_form_params("bigquery", config) do
    # credentials (service-account JSON) is secret — left blank on edit.
    %{}
    |> put_field("config_project_id", config["project_id"])
    |> put_field("config_dataset", config["dataset"])
    |> put_field("config_table", config["table"])
    |> put_field("config_location", config["location"])
  end

  defp config_form_params("kafka", config) do
    # sasl_password / ssl_keyfile are secret — left blank on edit.
    %{}
    |> put_field("config_bootstrap_servers", config["bootstrap_servers"])
    |> put_field("config_topic", config["topic"])
    |> put_field("config_auth_mode", config["auth_mode"])
    |> put_field("config_compression", config["compression"])
    |> put_field("config_transactional", bool_to_param(config["transactional"]))
    |> put_field("config_sasl_username", config["sasl_username"])
    |> put_field("config_ssl_certfile", config["ssl_certfile"])
  end

  defp config_form_params("snowflake", config) do
    # private_key / private_key_passphrase are secret — left blank on edit.
    %{}
    |> put_field("config_account", config["account"])
    |> put_field("config_warehouse", config["warehouse"])
    |> put_field("config_database", config["database"])
    |> put_field("config_schema", config["schema"])
    |> put_field("config_table", config["table"])
    |> put_field("config_user", config["user"])
  end

  defp config_form_params("redis", config) do
    # password is secret — left blank on edit.
    %{}
    |> put_field("config_host", config["host"])
    |> put_field("config_port", config["port"])
    |> put_field("config_db", config["db"])
    |> put_field("config_value_shape", config["value_shape"])
    |> put_field("config_key_template", config["key_template"])
    |> put_field("config_ttl_seconds", config["ttl_seconds"])
    |> put_field("config_auth_mode", config["auth_mode"])
    |> put_field("config_username", config["username"])
    |> put_field("config_tls", bool_to_param(config["tls"]))
    |> put_field("config_cluster", bool_to_param(config["cluster"]))
  end

  defp config_form_params("mongodb", config) do
    # uri (may embed a password) and password are secret — left blank on edit.
    %{}
    |> put_field("config_host", config["host"])
    |> put_field("config_port", config["port"])
    |> put_field("config_database", config["database"])
    |> put_field("config_collection", config["collection"])
    |> put_field("config_auth_mode", config["auth_mode"])
    |> put_field("config_username", config["username"])
    |> put_field("config_auth_source", config["auth_source"])
    |> put_field("config_tls", bool_to_param(config["tls"]))
    |> put_field("config_tls_ca_file", config["tls_ca_file"])
    |> put_field("config_tls_cert_file", config["tls_cert_file"])
    |> put_field("config_write_mode", config["write_mode"])
    |> put_field("config_upsert_keys", config["upsert_keys"])
    |> put_field("config_ttl_field", config["ttl_field"])
    |> put_field("config_ttl_seconds", config["ttl_seconds"])
  end

  defp config_form_params(_type, _config), do: %{}

  defp put_field(map, _key, nil), do: map
  defp put_field(map, _key, ""), do: map
  defp put_field(map, key, value), do: Map.put(map, key, to_string(value))

  defp put_columns(map, _key, columns) when columns in [nil, %{}], do: map

  defp put_columns(map, key, columns) when is_map(columns) do
    case Jason.encode(columns) do
      {:ok, json} -> Map.put(map, key, json)
      _ -> map
    end
  end

  defp put_columns(map, _key, _), do: map

  defp bool_to_param(true), do: "true"
  defp bool_to_param("true"), do: "true"
  defp bool_to_param(_), do: nil

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

  defp build_config(params, "bigquery") do
    %{}
    |> maybe_put("project_id", params["config_project_id"])
    |> maybe_put("dataset", params["config_dataset"])
    |> maybe_put("table", params["config_table"])
    |> maybe_put("credentials", params["config_credentials"])
    |> maybe_put("location", params["config_location"])
  end

  defp build_config(params, "kafka") do
    %{}
    |> maybe_put("bootstrap_servers", params["config_bootstrap_servers"])
    |> maybe_put("topic", params["config_topic"])
    |> maybe_put("auth_mode", params["config_auth_mode"])
    |> maybe_put("compression", params["config_compression"])
    |> maybe_put("sasl_username", params["config_sasl_username"])
    |> maybe_put("sasl_password", params["config_sasl_password"])
    |> maybe_put("ssl_certfile", params["config_ssl_certfile"])
    |> maybe_put("ssl_keyfile", params["config_ssl_keyfile"])
    |> Map.put("transactional", params["config_transactional"] == "true")
  end

  defp build_config(params, "snowflake") do
    %{}
    |> maybe_put("account", params["config_account"])
    |> maybe_put("warehouse", params["config_warehouse"])
    |> maybe_put("database", params["config_database"])
    |> maybe_put("schema", params["config_schema"])
    |> maybe_put("table", params["config_table"])
    |> maybe_put("user", params["config_user"])
    |> maybe_put("private_key", params["config_private_key"])
    |> maybe_put("private_key_passphrase", params["config_private_key_passphrase"])
  end

  defp build_config(params, "redis") do
    %{}
    |> maybe_put("host", params["config_host"])
    |> maybe_put("port", parse_int(params["config_port"]))
    |> maybe_put("db", parse_int(params["config_db"]))
    |> maybe_put("value_shape", params["config_value_shape"])
    |> maybe_put("key_template", params["config_key_template"])
    |> maybe_put("ttl_seconds", parse_int(params["config_ttl_seconds"]))
    |> maybe_put("auth_mode", params["config_auth_mode"])
    |> maybe_put("username", params["config_username"])
    |> maybe_put("password", params["config_password"])
    |> Map.put("tls", params["config_tls"] == "true")
    |> Map.put("cluster", params["config_cluster"] == "true")
  end

  defp build_config(params, "mongodb") do
    %{}
    |> maybe_put("uri", params["config_uri"])
    |> maybe_put("host", params["config_host"])
    |> maybe_put("port", parse_int(params["config_port"]))
    |> maybe_put("database", params["config_database"])
    |> maybe_put("collection", params["config_collection"])
    |> maybe_put("auth_mode", params["config_auth_mode"])
    |> maybe_put("username", params["config_username"])
    |> maybe_put("password", params["config_password"])
    |> maybe_put("auth_source", params["config_auth_source"])
    |> maybe_put("tls_ca_file", params["config_tls_ca_file"])
    |> maybe_put("tls_cert_file", params["config_tls_cert_file"])
    |> maybe_put("tls_key_file", params["config_tls_key_file"])
    |> maybe_put("write_mode", params["config_write_mode"])
    |> maybe_put("upsert_keys", params["config_upsert_keys"])
    |> maybe_put("ttl_field", params["config_ttl_field"])
    |> maybe_put("ttl_seconds", parse_int(params["config_ttl_seconds"]))
    |> Map.put("tls", params["config_tls"] == "true")
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
  defp pro_label("bigquery"), do: "BigQuery sinks"
  defp pro_label("kafka"), do: "Kafka sinks"
  defp pro_label("snowflake"), do: "Snowflake sinks"
  defp pro_label("redis"), do: "Redis sinks"
  defp pro_label("mongodb"), do: "MongoDB sinks"
  defp pro_label(type), do: "#{type} sinks"
end
