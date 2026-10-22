defmodule FluxWeb.SinkLive.Form do
  @moduledoc "LiveView for creating and editing sink configurations."
  use FluxWeb, :live_view

  import FluxWeb.Authorization

  alias Flux.Sinks
  alias Flux.Sinks.Sink

  # Sink types gated behind a Pro/EE license, mapped to their entitlement feature.
  @pro_sink_features %{
    "s3" => :s3_sink,
    "bigquery" => :bigquery_sink,
    "kafka" => :kafka_sink,
    "snowflake" => :snowflake_sink,
    "redis" => :redis_sink,
    "mongodb" => :mongodb_sink,
    "slack" => :slack_sink,
    "dynamodb" => :dynamodb_sink,
    "gcs" => :gcs_sink
  }

  # Picker tiles in display order: Community destinations, then the Pro/EE ones.
  @sink_type_options [
    %{type: "http", icon: "hero-globe-alt", label: "HTTP", sublabel: "Webhook / REST"},
    %{
      type: "postgres",
      icon: "hero-circle-stack",
      label: "Postgres",
      sublabel: "Flux DB or external"
    },
    %{type: "mysql", icon: "hero-server-stack", label: "MySQL", sublabel: "External database"},
    %{
      type: "parquet",
      icon: "hero-document-chart-bar",
      label: "Parquet",
      sublabel: "Data-lake files"
    },
    %{type: "email", icon: "hero-envelope", label: "Email", sublabel: "Notifications"},
    %{type: "s3", icon: "hero-cloud-arrow-up", label: "S3", sublabel: "Object storage"},
    %{type: "gcs", icon: "hero-cloud", label: "GCS", sublabel: "Google Cloud Storage"},
    %{type: "bigquery", icon: "hero-table-cells", label: "BigQuery", sublabel: "Warehouse"},
    %{type: "snowflake", icon: "hero-cube", label: "Snowflake", sublabel: "Warehouse"},
    %{type: "kafka", icon: "hero-queue-list", label: "Kafka", sublabel: "Event streaming"},
    %{type: "redis", icon: "hero-bolt", label: "Redis", sublabel: "Key-value store"},
    %{type: "mongodb", icon: "hero-document-text", label: "MongoDB", sublabel: "Document store"},
    %{
      type: "slack",
      icon: "hero-chat-bubble-left-right",
      label: "Slack",
      sublabel: "Messaging"
    },
    %{
      type: "dynamodb",
      icon: "hero-square-3-stack-3d",
      label: "DynamoDB",
      sublabel: "NoSQL key-value"
    }
  ]

  @impl true
  def mount(params, _session, socket) do
    {sink, action, title} =
      case params do
        %{"id" => id} ->
          sink = Sinks.get_sink(id, socket.assigns.current_scope.organization_id)
          {sink || %Sink{}, :edit, "Edit Sink"}

        _ ->
          {%Sink{config: %{}}, :new, "New Sink"}
      end

    changeset = Sinks.change_sink(sink, config_form_params(sink))

    {:ok,
     socket
     |> assign(:active_tab, :sinks)
     |> assign(:page_title, title)
     |> assign(:action, action)
     |> assign(:sink, sink)
     |> assign(:form, to_form(changeset))
     |> assign(:selected_type, sink.type)
     # A new sink opens on the destination picker; an existing one shows its
     # type collapsed to a summary row with a Change button.
     |> assign(:picking_type?, is_nil(sink.type))
     |> assign(:show_description?, sink.description not in [nil, ""])
     # The error summary only appears once a save has been attempted.
     |> assign(:show_errors?, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl">
      <nav aria-label="Breadcrumb" class="flex items-center gap-1.5 text-sm text-ink-subtle">
        <.link navigate={~p"/sinks"} class="transition-colors hover:text-base-content">Sinks</.link>
        <.icon name="hero-chevron-right" class="size-3.5" />
        <span class="text-base-content/80">{@page_title}</span>
      </nav>
      <h1 class="mt-2 text-2xl font-semibold tracking-tight text-base-content">{@page_title}</h1>
      <p class="mt-1 text-sm text-ink-subtle">
        A sink is where a pipeline delivers its output. Pick a destination, connect it, then name it.
      </p>

      <.form
        for={@form}
        id="sink-form"
        phx-change="validate"
        phx-submit="save"
        phx-hook=".FocusOnEvent"
        class="mt-6 space-y-4"
      >
        <.error_summary :if={@show_errors?} errors={error_items(@form, @selected_type)} />

        <%!-- On phones the open picker drops its card so two tiles fit side by side. --%>
        <section
          id="sink-destination"
          class={[
            "rounded-xl",
            if(@picking_type?,
              do: "sm:border sm:border-hairline sm:bg-surface-1",
              else: "border border-hairline bg-surface-1"
            )
          ]}
        >
          <.type_picker :if={@picking_type?} selected_type={@selected_type} />
          <.type_summary :if={!@picking_type?} type={@selected_type} />
        </section>

        <%= cond do %>
          <% is_nil(@selected_type) -> %>
            <.pending_section step={2} title="Connection" hint="Choose a destination first" />
            <.pending_section step={3} title="Details" hint="Name and description" />
          <% pro_locked?(@selected_type) -> %>
            <.pro_required type={@selected_type} />
          <% true -> %>
            <section
              id="sink-connection"
              class="rounded-xl border border-hairline bg-surface-1 p-5 sm:p-6"
            >
              <.section_heading step={2} title="Connection" />
              <.type_config_fields type={@selected_type} form={@form} sink={@sink} />
            </section>

            <section
              id="sink-details"
              class="rounded-xl border border-hairline bg-surface-1 p-5 sm:p-6"
            >
              <.section_heading step={3} title="Details" />
              <div class="max-w-lg">
                <.input
                  field={@form[:name]}
                  type="text"
                  label="Name"
                  placeholder="e.g. Analytics events"
                  required
                />
                <.input
                  :if={@show_description?}
                  field={@form[:description]}
                  type="textarea"
                  label="Description (optional)"
                  rows="2"
                />
              </div>
              <button
                :if={!@show_description?}
                type="button"
                id="sink-add-description"
                phx-click="show_description"
                class="btn btn-ghost btn-sm -ml-3 mt-1 text-base-content/80"
              >
                <.icon name="hero-plus" class="size-4" /> Add a description
              </button>
            </section>
        <% end %>

        <div
          id="sink-form-actions"
          class="sticky bottom-0 z-10 flex flex-wrap items-center gap-x-3 gap-y-2 border-t border-hairline bg-base-100/95 pt-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] backdrop-blur"
        >
          <p
            :if={submit_hint(@selected_type)}
            id="sink-submit-hint"
            class="w-full text-xs text-ink-subtle sm:w-auto sm:flex-1 sm:text-sm"
          >
            {submit_hint(@selected_type)}
          </p>
          <span :if={!submit_hint(@selected_type)} class="hidden sm:block sm:flex-1"></span>
          <.link navigate={~p"/sinks"} class="btn btn-ghost flex-1 sm:flex-none">Cancel</.link>
          <button
            type="submit"
            id="sink-submit"
            class="btn btn-primary flex-[2] sm:flex-none"
            disabled={submit_hint(@selected_type) != nil}
            aria-describedby={submit_hint(@selected_type) && "sink-submit-hint"}
          >
            <.icon name="hero-check" class="size-4" />
            {if @action == :new, do: "Create Sink", else: "Update Sink"}
          </button>
        </div>
      </.form>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".FocusOnEvent">
        // Picking or changing a destination swaps out the focused tile; the
        // server says where focus belongs once the new content is rendered.
        export default {
          mounted() {
            this.handleEvent("sink-form:focus", ({to}) => {
              this.el.querySelector(to)?.focus()
            })
          }
        }
      </script>
    </div>
    """
  end

  attr :step, :integer, required: true
  attr :title, :string, required: true
  attr :hint, :string, default: nil
  attr :done, :boolean, default: false

  defp section_heading(assigns) do
    ~H"""
    <div class="mb-5 flex flex-wrap items-center gap-x-3 gap-y-1">
      <span class={[
        "inline-flex size-6 shrink-0 items-center justify-center rounded-full text-xs font-semibold",
        @done && "border border-hairline-strong bg-surface-3 text-lavender-hover",
        !@done && "bg-primary text-primary-content"
      ]}>
        <.icon :if={@done} name="hero-check" class="size-3.5" />
        <span :if={!@done}>{@step}</span>
      </span>
      <h2 class="text-base font-semibold text-base-content">{@title}</h2>
      <span :if={@hint} class="text-sm text-ink-subtle">{@hint}</span>
    </div>
    """
  end

  attr :step, :integer, required: true
  attr :title, :string, required: true
  attr :hint, :string, required: true

  # A later step that can't start until a destination is chosen.
  defp pending_section(assigns) do
    ~H"""
    <section class="flex items-center gap-3 rounded-xl border border-hairline bg-surface-1 px-5 py-4 sm:px-6">
      <span class="inline-flex size-6 shrink-0 items-center justify-center rounded-full border border-hairline-strong text-xs font-semibold text-ink-subtle">
        {@step}
      </span>
      <h2 class="text-base font-semibold text-base-content/80">{@title}</h2>
      <span class="hidden text-sm text-ink-subtle sm:inline">{@hint}</span>
    </section>
    """
  end

  attr :selected_type, :string, default: nil

  defp type_picker(assigns) do
    pro = Enum.filter(@sink_type_options, &Map.has_key?(@pro_sink_features, &1.type))

    assigns =
      assign(assigns,
        community: @sink_type_options -- pro,
        pro: pro,
        any_locked?: Enum.any?(pro, &pro_locked?(&1.type))
      )

    ~H"""
    <div class="sm:p-6">
      <.section_heading step={1} title="Destination" hint="Where should the data go?" />

      <div role="group" aria-labelledby="sink-types-community">
        <h3 id="sink-types-community" class="mb-2.5 text-sm font-semibold text-base-content/90">
          Community <span class="font-normal text-ink-subtle">· included</span>
        </h3>
        <div class="grid grid-cols-2 gap-2 sm:grid-cols-[repeat(auto-fill,minmax(14rem,1fr))] sm:gap-3">
          <.sink_type_option
            :for={option <- @community}
            option={option}
            selected={@selected_type == option.type}
            locked={false}
          />
        </div>
      </div>

      <div role="group" aria-labelledby="sink-types-pro" class="mt-6">
        <h3
          id="sink-types-pro"
          class="mb-2.5 flex items-center gap-2 text-sm font-semibold text-base-content/90"
        >
          <.icon :if={@any_locked?} name="hero-lock-closed" class="size-3.5" /> Flux Pro
          <span class="hidden font-normal text-ink-subtle sm:inline">
            {if @any_locked?, do: "· requires a Flux Pro license", else: "· included in your license"}
          </span>
          <%!-- New tab, so a half-filled form isn't lost. --%>
          <.link
            :if={@any_locked?}
            id="sink-compare-plans"
            href={Flux.Marketing.pricing_url()}
            target="_blank"
            rel="noopener noreferrer"
            class="ml-auto inline-flex items-center gap-1 font-medium text-lavender-hover hover:underline"
          >
            Compare plans <.icon name="hero-arrow-top-right-on-square" class="size-3.5" />
            <span class="sr-only">(opens in a new tab)</span>
          </.link>
        </h3>
        <div class="grid grid-cols-2 gap-2 sm:grid-cols-[repeat(auto-fill,minmax(14rem,1fr))] sm:gap-3">
          <.sink_type_option
            :for={option <- @pro}
            option={option}
            selected={@selected_type == option.type}
            locked={pro_locked?(option.type)}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :option, :map, required: true
  attr :selected, :boolean, required: true
  attr :locked, :boolean, required: true

  # One destination tile. On phones the icon sits inline with the name and the
  # sublabel wraps underneath; from `sm` up the icon gets its own column.
  defp sink_type_option(assigns) do
    ~H"""
    <button
      type="button"
      id={"sink-type-#{@option.type}"}
      phx-click="select_type"
      phx-value-type={@option.type}
      aria-pressed={to_string(@selected)}
      class={[
        "grid grid-cols-[auto_minmax(0,1fr)_auto] content-center items-center gap-x-2 gap-y-0.5 rounded-lg border px-3 py-2.5 text-left transition-colors sm:gap-x-3 sm:p-3.5",
        "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lavender-hover",
        @selected && "border-primary bg-primary/10 ring-1 ring-inset ring-primary",
        !@selected && "border-hairline bg-surface-2 hover:border-hairline-strong hover:bg-surface-3"
      ]}
    >
      <span class="flex items-center justify-center sm:row-span-2 sm:size-9 sm:rounded-lg sm:bg-surface-3">
        <.icon
          name={@option.icon}
          class={["size-4 sm:size-5", if(@locked, do: "text-ink-subtle", else: "text-lavender-hover")]}
        />
      </span>
      <span class="truncate text-sm font-medium text-base-content">{@option.label}</span>
      <span
        :if={@locked}
        class="col-start-3 row-start-1 inline-flex items-center gap-1 text-ink-subtle sm:row-span-2 sm:rounded-full sm:border sm:border-hairline-strong sm:px-2 sm:py-0.5 sm:text-[11px] sm:font-semibold sm:tracking-wide sm:text-base-content/80"
      >
        <.icon name="hero-lock-closed" class="size-3.5 sm:size-3" />
        <span class="hidden sm:inline" aria-hidden="true">PRO</span>
        <span class="sr-only">Requires Flux Pro</span>
      </span>
      <%!-- Pinned to row 2, under the name. On phones it may run under the lock
           too. Start/end, not col-span, which would reset the start column. --%>
      <span class="col-start-2 col-end-4 row-start-2 text-xs text-ink-subtle sm:col-end-3">
        {@option.sublabel}
      </span>
    </button>
    """
  end

  attr :type, :string, required: true

  # The chosen destination, collapsed so the connection settings start near the top.
  defp type_summary(assigns) do
    assigns =
      assign(assigns,
        option: type_option(assigns.type),
        tier:
          if(Map.has_key?(@pro_sink_features, assigns.type), do: "Flux Pro", else: "Community")
      )

    ~H"""
    <div class="flex items-center gap-3 px-4 py-3.5 sm:px-6">
      <span class="hidden size-6 shrink-0 items-center justify-center rounded-full border border-hairline-strong bg-surface-3 text-lavender-hover sm:inline-flex">
        <.icon name="hero-check" class="size-3.5" />
      </span>
      <span class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-surface-3">
        <.icon name={@option.icon} class="size-5 text-lavender-hover" />
      </span>
      <div class="min-w-0">
        <p class="text-sm font-medium text-base-content">{@option.label}</p>
        <p class="text-xs text-ink-subtle">
          Destination · {@tier}
        </p>
      </div>
      <button
        type="button"
        id="sink-type-change"
        phx-click="change_type"
        class="btn btn-ghost btn-sm ml-auto border-hairline-strong"
      >
        Change
      </button>
    </div>
    """
  end

  attr :type, :string, required: true

  # Replaces the connection settings when the chosen type isn't licensed.
  defp pro_required(assigns) do
    community = Enum.reject(@sink_type_options, &Map.has_key?(@pro_sink_features, &1.type))

    assigns =
      assign(assigns,
        community_labels: community |> Enum.map(& &1.label) |> to_sentence(),
        activation_supported?: Flux.License.activation_supported?()
      )

    ~H"""
    <section
      id="sink-pro-required"
      class="rounded-xl border border-primary/50 bg-surface-2 p-5 sm:p-7"
    >
      <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:gap-5">
        <span class="flex size-11 shrink-0 items-center justify-center rounded-lg bg-primary/15 text-lavender-hover">
          <.icon name="hero-lock-closed" class="size-5" />
        </span>
        <div class="min-w-0 flex-1">
          <h2
            id="sink-pro-required-title"
            tabindex="-1"
            class="text-lg font-semibold tracking-tight text-base-content focus:outline-none"
          >
            {pro_label(@type)} are part of Flux Pro
          </h2>
          <p class="mt-2 max-w-prose text-sm leading-relaxed text-base-content/80">
            Community destinations — {@community_labels} — are always included. Upgrade to send pipeline output here too.
          </p>
          <div class="mt-5 flex flex-wrap items-center gap-3">
            <.link
              id="sink-view-pricing"
              href={Flux.Marketing.pricing_url()}
              target="_blank"
              rel="noopener noreferrer"
              class="btn btn-primary btn-sm"
            >
              View pricing <.icon name="hero-arrow-top-right-on-square" class="size-4" />
              <span class="sr-only">(opens in a new tab)</span>
            </.link>
            <button
              type="button"
              phx-click="change_type"
              class="btn btn-ghost btn-sm border-hairline-strong"
            >
              Choose another destination
            </button>
            <.link
              :if={@activation_supported?}
              navigate="/system/settings"
              class="text-sm font-medium text-lavender-hover hover:underline"
            >
              Already have a license? Activate it
            </.link>
          </div>
          <p
            :if={@type == "s3"}
            class="mt-5 flex gap-2 border-t border-hairline pt-4 text-sm text-ink-subtle"
          >
            <.icon name="hero-information-circle" class="mt-0.5 size-4 shrink-0" />
            <span>
              Need files in a bucket today? A Parquet sink writes to a directory you can mount from S3, GCS or Azure.
              <button
                type="button"
                phx-click="select_type"
                phx-value-type="parquet"
                class="font-medium text-lavender-hover hover:underline"
              >
                Use Parquet
              </button>
            </span>
          </p>
        </div>
      </div>
    </section>
    """
  end

  attr :errors, :list, required: true

  # Lists every problem from the last save attempt, each linking to its field.
  defp error_summary(%{errors: []} = assigns), do: ~H""

  defp error_summary(assigns) do
    ~H"""
    <div
      id="sink-form-errors"
      role="alert"
      class="flex gap-3 rounded-xl border border-error/50 bg-error/10 p-4"
    >
      <.icon name="hero-exclamation-circle" class="size-5 shrink-0 text-error" />
      <div class="min-w-0">
        <p class="text-sm font-semibold text-base-content">
          {if length(@errors) == 1,
            do: "Fix 1 issue to save this sink",
            else: "Fix #{length(@errors)} issues to save this sink"}
        </p>
        <ul class="mt-1.5 space-y-1 text-sm text-base-content/80">
          <li :for={{text, anchor} <- @errors}>
            <a :if={anchor} href={"#" <> anchor} class="underline-offset-2 hover:underline">
              {text}
            </a>
            <span :if={!anchor}>{text}</span>
          </li>
        </ul>
      </div>
    </div>
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
        required
      />
      <.input
        field={@form[:config_method]}
        type="select"
        label="HTTP Method"
        options={["POST", "PUT", "PATCH"]}
      />
      <.input
        field={@form[:config_timeout]}
        type="number"
        label="Timeout (ms)"
        placeholder="Default: 30000"
      />
    </div>
    """
  end

  defp type_config_fields(%{type: "s3"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.input
        field={@form[:config_bucket]}
        type="text"
        label="Bucket Name"
        placeholder="my-bucket"
        required
      />
      <.input
        field={@form[:config_key_template]}
        type="text"
        label="Key Template"
        placeholder="data/{date}/{id}.json"
        required
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

  # Rendered only on a licensed build (Community shows the upgrade prompt instead).
  defp type_config_fields(%{type: "gcs"} = assigns) do
    assigns = assign(assigns, format: cfg(assigns.form, "config_format") || "ndjson")

    ~H"""
    <div class="space-y-4">
      <.input
        field={@form[:config_bucket]}
        type="text"
        label="Bucket Name"
        placeholder="my-bucket"
        required
      />
      <.input
        field={@form[:config_object_template]}
        type="text"
        label="Object Name Template"
        placeholder="{pipeline_id}/{date}/{timestamp}-{uid}"
      />
      <p class="text-xs text-base-content/60 -mt-2">
        Placeholders: {"{pipeline_id}"}, {"{sink_id}"}, {"{date}"}, {"{hour}"}, {"{timestamp}"}, {"{uid}"}.
        The file extension is added for you.
      </p>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:config_format]}
          type="select"
          label="Format"
          options={[{"Newline-delimited JSON", "ndjson"}, {"Parquet", "parquet"}]}
        />
        <.input
          field={@form[:config_compression]}
          type="select"
          label="Compression"
          options={gcs_compression_options(@format)}
        />
      </div>
      <.input
        field={@form[:config_credentials]}
        type="textarea"
        label="Service Account JSON"
        placeholder="Leave blank to use GOOGLE_APPLICATION_CREDENTIALS / Workload Identity"
      />
      <p class="text-xs text-base-content/60 -mt-2">
        Paste a service-account key with <code>storage.objects.create</code>
        on the bucket, or leave blank to fall back to Application Default Credentials
        (e.g. Workload Identity on GKE).
      </p>
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <.input
          field={@form[:config_max_records]}
          type="number"
          label="Flush After Records"
          placeholder="Default: 10000"
        />
        <.input
          field={@form[:config_max_mb]}
          type="number"
          label="Flush After MB"
          placeholder="Default: 100"
        />
        <.input
          field={@form[:config_max_interval_seconds]}
          type="number"
          label="Flush After Seconds"
          placeholder="Default: 60"
        />
      </div>
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
      <.input
        field={@form[:config_table]}
        type="text"
        label="Table Name"
        placeholder="e.g. events"
        required
      />
      <.input
        :if={cfg(@form, "config_mode") == "external"}
        field={@form[:config_database_url]}
        type="text"
        label="Database URL"
        placeholder="postgres://user:pass@host:5432/db"
        required
      />
      <.input
        field={@form[:config_columns]}
        type="textarea"
        label="Column Mapping (JSON)"
        placeholder='{"event_type": "type", "payload.user_id": "user_id"}'
        required
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
        required
      />
      <p class="text-xs text-base-content/60 -mt-2">
        Flux connects out to this database — make sure its host/port allows the Flux
        server's egress IP. See <code>docs/connectors/external-databases.md</code>.
      </p>
      <.input
        field={@form[:config_table]}
        type="text"
        label="Table Name"
        placeholder="e.g. events"
        required
      />
      <.input
        field={@form[:config_columns]}
        type="textarea"
        label="Column Mapping (JSON)"
        placeholder={~s({"event_type": "type", "payload.user_id": "user_id"})}
        required
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

  defp type_config_fields(%{type: "parquet"} = assigns) do
    assigns =
      assign(assigns,
        base_dir: Flux.Sink.Adapters.Parquet.Paths.base_dir(),
        default_path_template: Flux.Sink.Adapters.Parquet.Settings.default_path_template(),
        schema_types: Flux.Sink.Adapters.Parquet.Schema.explicit_type_names()
      )

    ~H"""
    <div class="space-y-4">
      <.input
        field={@form[:config_directory]}
        type="text"
        label="Directory"
        placeholder="e.g. events"
        required
      />
      <p class="text-xs text-base-content/60 -mt-2">
        Relative to the Parquet base directory <code>{@base_dir}</code>
        (set by <code>FLUX_PARQUET_BASE_DIR</code>). Mount a bucket there to land files in
        S3, GCS or Azure — see <code>docs/connectors/parquet.md</code>.
      </p>
      <.input
        field={@form[:config_partition_template]}
        type="text"
        label="Partition Template (optional)"
        placeholder="year={yyyy}/month={MM}/day={dd}/"
      />
      <p class="text-xs text-base-content/60 -mt-2">
        Placeholders: {"{yyyy}"}, {"{MM}"}, {"{dd}"}, {"{HH}"}, {"{date}"}, {"{pipeline_id}"},
        or any record field such as {"{region}"} or {"{user.tier}"}.
      </p>
      <.input
        field={@form[:config_path_template]}
        type="text"
        label="File Path Template"
        placeholder={@default_path_template}
      />
      <p class="text-xs text-base-content/60 -mt-2">
        Placeholders: {"{pipeline_id}"}, {"{partition}"}, {"{timestamp}"}, {"{date}"}, {"{seq}"}, {"{uid}"}.
        Must include {"{uid}"} or {"{timestamp}"} and end in <code>.parquet</code>.
      </p>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:config_compression]}
          type="select"
          label="Compression"
          options={[
            {"Snappy (default)", "snappy"},
            {"Zstandard", "zstd"},
            {"Gzip", "gzip"},
            {"None", "none"}
          ]}
        />
        <.input
          field={@form[:config_compression_level]}
          type="number"
          label="Compression Level (optional)"
          placeholder="gzip 1–9, zstd -7–22"
        />
      </div>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:config_max_rows]}
          type="number"
          label="Rotate After Rows"
          placeholder="Default: 100000"
        />
        <.input
          field={@form[:config_max_interval_seconds]}
          type="number"
          label="Rotate After Seconds"
          placeholder="Default: 600"
        />
      </div>
      <.input
        field={@form[:config_schema]}
        type="textarea"
        label="Explicit Schema (JSON, optional)"
        placeholder={~s({"id": "integer", "email": "string", "created_at": "timestamp"})}
      />
      <p class="text-xs text-base-content/60 -mt-2">
        Leave blank to infer the schema from incoming records. Types: {Enum.join(@schema_types, ", ")}.
      </p>
      <.input
        field={@form[:config_schema_mode]}
        type="select"
        label="On Schema Change (inferred schemas)"
        options={[
          {"Rotate to a new file with the widened schema", "rotate"},
          {"Reject records that don't match", "strict"}
        ]}
      />
    </div>
    """
  end

  defp type_config_fields(%{type: "email"} = assigns) do
    provider = cfg(assigns.form, "config_provider") || "smtp"

    # A saved secret is only kept while the provider stays the same (see
    # carried_config/3), so a new sink or a provider switch needs fresh ones.
    keeps_secrets? =
      not is_nil(assigns.form.data.id) and
        (assigns.form.data.config || %{})["provider"] == provider

    # Mirrors the adapter's fallback for a blank port (Email.smtp_config/1).
    default_port = if cfg(assigns.form, "config_security") == "ssl", do: 465, else: 587

    assigns =
      assign(assigns,
        provider: provider,
        keeps_secrets?: keeps_secrets?,
        default_port: default_port
      )

    ~H"""
    <div class="space-y-6">
      <div class="space-y-4">
        <.input
          field={@form[:config_provider]}
          type="select"
          label="Send With"
          options={[
            {"SMTP server", "smtp"},
            {"Flux system mailer", "system"},
            {"SendGrid", "sendgrid"},
            {"Mailgun", "mailgun"},
            {"Postmark", "postmark"},
            {"Amazon SES", "amazon_ses"}
          ]}
        />

        <div :if={@provider == "smtp"} id="email-smtp-fields" class="space-y-4">
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div class="sm:col-span-2">
              <.input
                field={@form[:config_host]}
                type="text"
                label="SMTP Host"
                placeholder="smtp.example.com"
                required
              />
            </div>
            <.input
              field={@form[:config_port]}
              type="number"
              label="Port"
              placeholder={"Default: #{@default_port}"}
            />
          </div>
          <.input
            field={@form[:config_security]}
            type="select"
            label="Encryption"
            options={[
              {"STARTTLS (port 587)", "starttls"},
              {"SSL/TLS (port 465)", "ssl"},
              {"None (internal relays only)", "none"}
            ]}
          />
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input field={@form[:config_username]} type="text" label="Username (optional)" />
            <.input
              field={@form[:config_password]}
              type="password"
              label="Password"
              placeholder={if @keeps_secrets?, do: "Leave blank to keep current", else: ""}
            />
          </div>
          <.input
            field={@form[:config_tls_skip_verify]}
            type="checkbox"
            label="Skip TLS certificate verification (insecure — self-signed internal relays only)"
          />
        </div>

        <div
          :if={@provider == "system"}
          id="email-system-note"
          class="rounded-lg bg-base-200/60 p-3 text-sm text-base-content/70"
        >
          Sends through the mail server this Flux instance is configured with
          (<code>FLUX_SMTP_*</code>). The From address defaults to <code>FLUX_MAIL_FROM_ADDRESS</code>.
        </div>

        <div
          :if={@provider in ["sendgrid", "mailgun", "postmark"]}
          id="email-api-fields"
          class="space-y-4"
        >
          <.input
            field={@form[:config_api_key]}
            type="password"
            label="API Key"
            placeholder={if @keeps_secrets?, do: "Leave blank to keep current", else: ""}
            required={!@keeps_secrets?}
          />
          <div :if={@provider == "mailgun"} class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input
              field={@form[:config_domain]}
              type="text"
              label="Sending Domain"
              placeholder="mg.example.com"
              required
            />
            <.input
              field={@form[:config_region]}
              type="select"
              label="Region"
              options={[{"US", "us"}, {"EU", "eu"}]}
            />
          </div>
        </div>

        <div :if={@provider == "amazon_ses"} id="email-ses-fields" class="space-y-4">
          <.input
            field={@form[:config_region]}
            type="text"
            label="AWS Region"
            placeholder="us-east-1"
            required
          />
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input field={@form[:config_access_key]} type="text" label="Access Key ID" required />
            <.input
              field={@form[:config_secret_access_key]}
              type="password"
              label="Secret Access Key"
              placeholder={if @keeps_secrets?, do: "Leave blank to keep current", else: ""}
              required={!@keeps_secrets?}
            />
          </div>
        </div>
      </div>

      <div class="space-y-4">
        <h3 class="text-sm font-semibold text-base-content/80">Sender &amp; Recipients</h3>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <.input
            field={@form[:config_from]}
            type="email"
            label={if @provider == "system", do: "From Address (optional)", else: "From Address"}
            placeholder="alerts@example.com"
            maxlength="254"
            required={@provider != "system"}
          />
          <.input
            field={@form[:config_from_name]}
            type="text"
            label="From Name (optional)"
            placeholder="Pipeline Alerts"
            maxlength="78"
          />
        </div>
        <.input
          field={@form[:config_reply_to]}
          type="email"
          label="Reply-To (optional)"
          placeholder="ops@example.com"
          maxlength="254"
        />
        <div :for={{field, label, required} <- recipient_fields()} id={"email-#{field}"}>
          <.input
            field={@form[field]}
            type="textarea"
            label={label}
            rows="2"
            placeholder="ops@example.com, oncall@example.com"
            required={required}
          />
          <p
            :for={msg <- recipient_errors(@form, field)}
            class="-mt-1 flex gap-2 items-center text-sm text-error"
          >
            <.icon name="hero-exclamation-circle" class="size-5 shrink-0" />{msg}
          </p>
        </div>
        <p class="text-xs text-base-content/60">
          Separate addresses with commas or new lines. Up to {Flux.EmailAddress.max_recipients()} recipients in total.
        </p>
      </div>

      <div class="space-y-4">
        <h3 class="text-sm font-semibold text-base-content/80">Message</h3>
        <.input
          field={@form[:config_subject]}
          type="text"
          label="Subject"
          placeholder="Order {order.id} failed"
          required
        />
        <.input
          field={@form[:config_html_body]}
          type="textarea"
          label="HTML Body (optional)"
          rows="5"
          placeholder="<p>Order <strong>{order.id}</strong> failed: {error.message}</p>"
        />
        <.input
          field={@form[:config_text_body]}
          type="textarea"
          label="Plain-Text Body (optional)"
          rows="4"
          placeholder="Order {order.id} failed: {error.message}"
        />
        <p class="text-xs text-base-content/60 -mt-2">
          <code phx-no-curly-interpolation>{field}</code>
          placeholders (dot-paths supported) are filled from each record. Values are
          HTML-escaped in the HTML body. Leave both bodies blank to send the record as JSON.
        </p>
      </div>

      <div class="space-y-4">
        <h3 class="text-sm font-semibold text-base-content/80">Rate Limit</h3>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <.input
            field={@form[:config_max_per_minute]}
            type="number"
            label="Max Emails per Minute"
            placeholder="Default: 30"
            min="1"
          />
          <.input
            field={@form[:config_max_wait_ms]}
            type="number"
            label="Max Wait When Limited (ms)"
            placeholder="Default: 30000"
            min="0"
          />
        </div>
        <p class="text-xs text-base-content/60 -mt-2">
          Records over the limit wait for the next minute, then are dropped. Applies per Flux node.
        </p>
      </div>
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
        required
      />
      <.input
        field={@form[:config_dataset]}
        type="text"
        label="Dataset"
        placeholder="analytics"
        required
      />
      <.input
        field={@form[:config_table]}
        type="text"
        label="Table"
        placeholder="e.g. events"
        required
      />
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
        required
      />
      <.input
        field={@form[:config_topic]}
        type="text"
        label="Topic"
        placeholder="e.g. events"
        required
      />
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
        required={cfg(@form, "config_auth_mode") in ~w(sasl_plain sasl_scram_256 sasl_scram_512)}
      />
      <.input
        field={@form[:config_sasl_password]}
        type="password"
        label="SASL Password"
        placeholder="Required for SASL auth modes"
        required={cfg(@form, "config_auth_mode") in ~w(sasl_plain sasl_scram_256 sasl_scram_512)}
      />
      <.input
        field={@form[:config_ssl_certfile]}
        type="text"
        label="Client Certificate Path (mTLS)"
        placeholder="/etc/flux/certs/client.pem"
        required={cfg(@form, "config_auth_mode") == "mtls"}
      />
      <.input
        field={@form[:config_ssl_keyfile]}
        type="password"
        label="Client Key Path (mTLS)"
        placeholder="/etc/flux/certs/client.key"
        required={cfg(@form, "config_auth_mode") == "mtls"}
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
        required
      />
      <p class="text-xs text-base-content/60 -mt-2">
        Flux egresses to <code>&lt;account&gt;.snowflakecomputing.com</code> over HTTPS
        (443) — make sure the Flux node's outbound/NAT allows it.
      </p>
      <.input
        field={@form[:config_warehouse]}
        type="text"
        label="Warehouse"
        placeholder="compute_wh"
        required
      />
      <.input
        field={@form[:config_database]}
        type="text"
        label="Database"
        placeholder="analytics"
        required
      />
      <.input field={@form[:config_schema]} type="text" label="Schema" placeholder="public" required />
      <.input
        field={@form[:config_table]}
        type="text"
        label="Table"
        placeholder="e.g. events"
        required
      />
      <.input
        field={@form[:config_user]}
        type="text"
        label="User"
        placeholder="flux_loader"
        required
      />
      <.input
        field={@form[:config_private_key]}
        type="password"
        label="Private Key (PEM)"
        placeholder="-----BEGIN PRIVATE KEY-----"
        required
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
          <.input
            field={@form[:config_host]}
            type="text"
            label="Host"
            placeholder="redis.internal"
            required
          />
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
        required
      />
      <.input
        field={@form[:config_key_template]}
        type="text"
        label="Key Template"
        placeholder="scores:{id}"
        required
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
        required={cfg(@form, "config_auth_mode") == "acl"}
      />
      <.input
        field={@form[:config_password]}
        type="password"
        label="Password"
        placeholder="Required for password / ACL auth"
        required={cfg(@form, "config_auth_mode") in ~w(password acl)}
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
      <.input field={@form[:config_database]} type="text" label="Database" placeholder="e.g. events" />
      <.input
        field={@form[:config_collection]}
        type="text"
        label="Collection"
        placeholder="raw"
        required
      />
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
        required={cfg(@form, "config_auth_mode") == "scram"}
      />
      <.input
        field={@form[:config_password]}
        type="password"
        label="Password (SCRAM)"
        placeholder="Required for SCRAM auth"
        required={cfg(@form, "config_auth_mode") == "scram"}
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
        required={cfg(@form, "config_auth_mode") == "x509"}
      />
      <.input
        field={@form[:config_tls_key_file]}
        type="password"
        label="Client Key Path (X.509)"
        placeholder="/etc/flux/certs/client.key"
        required={cfg(@form, "config_auth_mode") == "x509"}
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
        required={cfg(@form, "config_write_mode") == "upsert"}
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

  # Rendered only on a licensed build (Community shows the upgrade prompt instead).
  defp type_config_fields(%{type: "slack"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.input
        field={@form[:config_auth_mode]}
        type="select"
        label="Auth Mode"
        options={[
          {"Incoming Webhook URL", "webhook"},
          {"Bot token (chat.postMessage)", "bot_token"}
        ]}
      />
      <.input
        field={@form[:config_webhook_url]}
        type="password"
        label="Webhook URL (webhook mode)"
        placeholder="https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXX"
        required={cfg(@form, "config_auth_mode") in [nil, "webhook"]}
      />
      <p class="text-xs text-base-content/60 -mt-2">
        Create an Incoming Webhook in your Slack app; the URL embeds a secret token, so it is
        write-only here and left blank when editing.
      </p>
      <.input
        field={@form[:config_bot_token]}
        type="password"
        label="Bot Token (bot-token mode)"
        placeholder="xoxb-…"
        required={cfg(@form, "config_auth_mode") == "bot_token"}
      />
      <.input
        field={@form[:config_channel]}
        type="text"
        label="Channel"
        placeholder="#alerts (required for bot-token mode)"
        required={cfg(@form, "config_auth_mode") == "bot_token"}
      />
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:config_username]}
          type="text"
          label="Bot Username (optional)"
          placeholder="Flux"
        />
        <.input
          field={@form[:config_icon_emoji]}
          type="text"
          label="Icon Emoji (optional)"
          placeholder=":rocket:"
        />
      </div>
      <.input
        field={@form[:config_message_template]}
        type="text"
        label="Message Template (optional)"
        placeholder="Alert: {type} on {host}"
      />
      <p class="text-xs text-base-content/60 -mt-2">
        Interpolates <code phx-no-curly-interpolation>{field}</code> placeholders (dot-paths
        supported) from each record. Leave blank to post the JSON-encoded record.
      </p>
      <.input
        field={@form[:config_blocks_template]}
        type="textarea"
        label="Block Kit Blocks (optional JSON)"
        placeholder={~s([{"type":"section","text":{"type":"mrkdwn","text":"{message}"}}])}
      />
      <p class="text-xs text-base-content/60 -mt-2">
        A JSON array of
        <a class="link" href="https://api.slack.com/block-kit" target="_blank">Block Kit</a>
        blocks for rich messages. Supports the same <code phx-no-curly-interpolation>{field}</code>
        interpolation.
      </p>
    </div>
    """
  end

  # Rendered only on a licensed build (Community shows the upgrade prompt instead).
  defp type_config_fields(%{type: "dynamodb"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.input
        field={@form[:config_table_name]}
        type="text"
        label="Table Name"
        placeholder="events"
        required
      />
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:config_partition_key]}
          type="text"
          label="Partition Key"
          placeholder="pk"
          required
        />
        <.input
          field={@form[:config_sort_key]}
          type="text"
          label="Sort Key (optional)"
          placeholder="sk"
        />
      </div>
      <p class="text-xs text-base-content/60 -mt-2">
        The table's key attributes. Every record must carry them; they are checked against the
        table's key schema by Test connection.
      </p>
      <.input field={@form[:config_region]} type="text" label="Region" placeholder="us-east-1" />
      <.input
        field={@form[:config_endpoint]}
        type="url"
        label="Custom Endpoint (optional)"
        placeholder="http://localhost:4566"
      />
      <.input
        field={@form[:config_auth_mode]}
        type="select"
        label="Auth Mode"
        options={[
          {"IAM role (ambient credentials)", "iam_role"},
          {"Static access key", "static"},
          {"Assume role (cross-account)", "assume_role"}
        ]}
      />
      <div :if={cfg(@form, "config_auth_mode") == "static"} class="space-y-4">
        <.input
          field={@form[:config_access_key_id]}
          type="text"
          label="Access Key ID"
          placeholder="AKIA…"
          required
        />
        <.input
          field={@form[:config_secret_access_key]}
          type="password"
          label="Secret Access Key"
          required
        />
        <.input
          field={@form[:config_session_token]}
          type="password"
          label="Session Token (optional)"
          placeholder="For temporary credentials"
        />
        <.input
          :if={stored_session_token?(@sink)}
          field={@form[:config_clear_session_token]}
          type="checkbox"
          label="Remove the stored session token"
        />
        <p class="text-xs text-base-content/60 -mt-2">
          Leave the secrets blank to keep the stored ones. Entering a new secret access key
          without a session token also removes the stored token, which only works with the
          key pair it was issued for.
        </p>
      </div>
      <div :if={cfg(@form, "config_auth_mode") == "assume_role"} class="space-y-4">
        <.input
          field={@form[:config_role_arn]}
          type="text"
          label="Role ARN"
          placeholder="arn:aws:iam::123456789012:role/flux-dynamodb"
          required
        />
        <.input
          field={@form[:config_external_id]}
          type="text"
          label="External ID (optional)"
        />
      </div>
      <.input
        field={@form[:config_write_mode]}
        type="select"
        label="Write Mode"
        options={[
          {"Put (overwrite by key)", "put"},
          {"Insert if absent (first write wins)", "if_absent"},
          {"Put if newer (version attribute)", "if_newer"}
        ]}
      />
      <.input
        :if={cfg(@form, "config_write_mode") == "if_newer"}
        field={@form[:config_version_attribute]}
        type="text"
        label="Version Attribute"
        placeholder="version"
        required
      />
      <p class="text-xs text-base-content/60 -mt-2">
        Conditional modes make redelivery idempotent: a duplicate or older record is skipped
        rather than overwriting newer data.
      </p>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:config_ttl_attribute]}
          type="text"
          label="TTL Attribute (optional)"
          placeholder="expires_at"
        />
        <.input
          field={@form[:config_ttl_seconds]}
          type="number"
          label="TTL (seconds)"
          placeholder="Expire items after N seconds"
        />
      </div>
      <p class="text-xs text-base-content/60 -mt-2">
        When both are set, each item gets an epoch expiry. Enable TTL on that attribute in the
        table settings so DynamoDB deletes expired items.
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
    # A new destination starts clean: the last save's problems were about the old one.
    {:noreply,
     socket
     |> clear_flash()
     |> assign(selected_type: type, picking_type?: false, show_errors?: false)
     |> focus(destination_focus(type))}
  end

  def handle_event("change_type", _params, socket) do
    {:noreply,
     socket
     |> assign(:picking_type?, true)
     |> focus("#sink-type-#{socket.assigns.selected_type}")}
  end

  def handle_event("show_description", _params, socket) do
    {:noreply, assign(socket, :show_description?, true)}
  end

  def handle_event("validate", %{"sink" => params}, socket) do
    type = socket.assigns.selected_type
    params = merge_config_params(params, type, socket.assigns.sink)

    changeset =
      socket.assigns.sink
      |> Sinks.change_sink(params)
      |> place_config_errors(type)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"sink" => params}, socket) do
    permission = if socket.assigns.action == :new, do: :create_sink, else: :edit_sink

    authorize(socket, permission, fn ->
      # The submit button is disabled for a locked type; this guards a forged event.
      if pro_locked?(socket.assigns.selected_type) do
        {:noreply, socket}
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
        {:noreply, show_save_errors(socket, changeset)}
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
        {:noreply, show_save_errors(socket, changeset)}
    end
  end

  # A failed save shows each problem under its field plus a summary banner at
  # the top of the form, rather than a toast that outlives the attempt.
  defp show_save_errors(socket, changeset) do
    changeset = place_config_errors(changeset, socket.assigns.selected_type)
    assign(socket, form: to_form(changeset), show_errors?: true)
  end

  # Adapters report config problems as ":config" errors whose text starts with
  # the config key ("url is required", "rate_limit.max_wait_ms must be ...").
  # Each is moved onto the `config_*` form field it's about so it renders under
  # that input; a message that names no field stays on :config for the banner.
  defp place_config_errors(changeset, type) do
    errors =
      Enum.map(changeset.errors, fn
        {:config, {msg, opts}} -> place_config_error(type, msg, opts)
        error -> error
      end)

    %{changeset | errors: errors}
  end

  defp place_config_error(type, msg, opts) do
    with [_, key, sep, rest] <- Regex.run(~r/^([a-z_]+(?:\.[a-z_]+)?)(:?) (.+)$/s, msg),
         {:ok, field} <- config_error_field(type, key),
         # Recipient fields already list per-address problems live as you type
         # (recipient_errors/2), so their "to: ..." summary would repeat them.
         false <- sep == ":" and field in [:config_to, :config_cc, :config_bcc] do
      {field, {rest, opts}}
    else
      _ -> {:config, {msg, opts}}
    end
  end

  # Config keys whose form field isn't simply "config_<key>".
  @config_error_fields %{
    {"http", "timeout_ms"} => :config_timeout,
    {"s3", "access_key_id"} => :config_access_key,
    {"s3", "secret_access_key"} => :config_secret_key,
    {"gcs", "max_bytes"} => :config_max_mb,
    {"email", "rate_limit.max_per_minute"} => :config_max_per_minute,
    {"email", "rate_limit.max_wait_ms"} => :config_max_wait_ms,
    {"email", "tls_verify"} => :config_tls_skip_verify
  }

  defp config_error_field(type, key) do
    case Map.fetch(@config_error_fields, {type, key}) do
      {:ok, field} ->
        {:ok, field}

      :error ->
        # Only atoms the form already uses can match, so this never mints new ones.
        try do
          {:ok, String.to_existing_atom("config_" <> key)}
        rescue
          ArgumentError -> :error
        end
    end
  end

  # Moves keyboard focus once the patch lands (see the .FocusOnEvent hook):
  # choosing a destination removes the tile that had focus.
  defp focus(socket, selector), do: push_event(socket, "sink-form:focus", %{to: selector})

  # A licensed type continues at its first setting; a locked one at the
  # upgrade panel that replaces the settings.
  defp destination_focus(type) do
    if pro_locked?(type),
      do: "#sink-pro-required-title",
      else: "#sink-connection :is(input, select, textarea):not([type=hidden])"
  end

  # The banner's lines, as {text, anchor-id-or-nil}: "URL is required" links to
  # the URL input; a message that names no field is shown as-is.
  # Ordered as the page shows the fields, so following the banner walks down
  # the form. Anything not on the page (e.g. a :config message) goes last.
  defp error_items(form, type) do
    order = displayed_fields(form, type)
    position = fn {field, _} -> Enum.find_index(order, &(&1 == field)) || length(order) end

    # Changeset errors are newest-first; reversing first keeps ties in
    # validation order, since sort_by is stable.
    errors = form.errors |> Enum.reverse() |> Enum.sort_by(position)

    for {field, error} <- errors do
      message = translate_error(error)

      case field do
        :config -> {upcase_first(message), nil}
        field -> {"#{error_field_name(field)} #{message}", form[field].id}
      end
    end
  end

  # The selected type's settings in rendered order, then the Details fields.
  # Read from the rendered settings rather than a hand-kept list, so it follows
  # the form as fields are added or shown conditionally (e.g. per provider).
  defp displayed_fields(_form, nil), do: [:name, :description]

  defp displayed_fields(form, type) do
    # No stored sink: only edit-only controls depend on it, and none carry errors.
    html =
      %{type: type, form: form, sink: nil, __changed__: nil}
      |> type_config_fields()
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    config_fields =
      ~r/name="#{Regex.escape(form.name)}\[(config_\w+)\]/
      |> Regex.scan(html, capture: :all_but_first)
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.map(&String.to_existing_atom/1)

    config_fields ++ [:name, :description]
  end

  @label_words %{
    "url" => "URL",
    "uri" => "URI",
    "id" => "ID",
    "api" => "API",
    "tls" => "TLS",
    "ssl" => "SSL",
    "ttl" => "TTL",
    "db" => "DB",
    "ms" => "(ms)"
  }

  defp error_field_name(field) do
    field
    |> Atom.to_string()
    |> String.replace_prefix("config_", "")
    |> String.split("_")
    |> Enum.map_join(" ", &Map.get(@label_words, &1, &1))
    |> upcase_first()
  end

  defp upcase_first(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp upcase_first(string), do: string

  # Merge freshly built config over the sink's stored config so that any field
  # the user left blank (dropped by `maybe_put/3` — notably secrets) falls back
  # to the persisted value instead of being silently wiped on edit. A field a
  # builder puts as nil was cleared on purpose and is removed. When the type
  # changes we start from an empty base so stale keys aren't carried over.
  defp merge_config_params(params, type, sink) do
    built = build_config(params, type)
    base = if type == sink.type, do: carried_config(type, sink.config || %{}, built), else: %{}

    config =
      base
      |> Map.merge(built)
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    params
    |> Map.put("type", type)
    |> Map.put("config", config)
  end

  # An email sink's secrets belong to its provider. SendGrid, Postmark and
  # Mailgun all store their key as "api_key", so carrying a blank secret over a
  # provider switch would save the old provider's key under the new one and
  # every send would then fail to authenticate. On a switch the stored secrets
  # are dropped, and validation asks for the new provider's credentials.
  @email_secret_keys ~w(password api_key secret_access_key)

  defp carried_config("email", config, built) do
    if config["provider"] == built["provider"],
      do: config,
      else: Map.drop(config, @email_secret_keys)
  end

  # A DynamoDB sink's stored AWS secrets belong to static auth. On a switch to
  # another mode they are dropped (access_key_id is cleared by build_config/2),
  # so the adapter can't go on signing with the old keys. A session token only
  # works with the key pair it was issued for, so a new secret entered without
  # a new token drops the stored token.
  @aws_static_secret_keys ~w(secret_access_key session_token)

  defp carried_config("dynamodb", config, built) do
    cond do
      Map.get(built, "auth_mode", "iam_role") != "static" ->
        Map.drop(config, @aws_static_secret_keys)

      Map.has_key?(built, "secret_access_key") and not Map.has_key?(built, "session_token") ->
        Map.delete(config, "session_token")

      true ->
        config
    end
  end

  defp carried_config(_type, config, _built), do: config

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

  defp config_form_params("parquet", config) do
    %{}
    |> put_field("config_directory", config["directory"])
    |> put_field("config_path_template", config["path_template"])
    |> put_field("config_partition_template", config["partition_template"])
    |> put_field("config_compression", config["compression"])
    |> put_field("config_compression_level", config["compression_level"])
    |> put_field("config_max_rows", config["max_rows"])
    |> put_field("config_max_interval_seconds", config["max_interval_seconds"])
    |> put_field("config_schema_mode", config["schema_mode"])
    |> put_columns("config_schema", config["schema"])
  end

  defp config_form_params("email", config) do
    # password, api_key and secret_access_key are secret — left blank on edit.
    rate = if is_map(config["rate_limit"]), do: config["rate_limit"], else: %{}

    %{}
    |> put_field("config_provider", config["provider"])
    |> put_field("config_host", config["host"])
    |> put_field("config_port", config["port"])
    |> put_field("config_security", config["security"])
    |> put_field("config_username", config["username"])
    |> put_field("config_tls_skip_verify", bool_to_param(config["tls_verify"] == false))
    |> put_field("config_domain", config["domain"])
    |> put_field("config_region", config["region"])
    |> put_field("config_access_key", config["access_key"])
    |> put_field("config_from", config["from"])
    |> put_field("config_from_name", config["from_name"])
    |> put_field("config_reply_to", config["reply_to"])
    |> put_field("config_to", join_addresses(config["to"]))
    |> put_field("config_cc", join_addresses(config["cc"]))
    |> put_field("config_bcc", join_addresses(config["bcc"]))
    |> put_field("config_subject", config["subject"])
    |> put_field("config_html_body", config["html_body"])
    |> put_field("config_text_body", config["text_body"])
    |> put_field("config_max_per_minute", rate["max_per_minute"])
    |> put_field("config_max_wait_ms", rate["max_wait_ms"])
  end

  defp config_form_params("bigquery", config) do
    # credentials (service-account JSON) is secret — left blank on edit.
    %{}
    |> put_field("config_project_id", config["project_id"])
    |> put_field("config_dataset", config["dataset"])
    |> put_field("config_table", config["table"])
    |> put_field("config_location", config["location"])
  end

  defp config_form_params("gcs", config) do
    # credentials (service-account JSON) is secret — left blank on edit.
    %{}
    |> put_field("config_bucket", config["bucket"])
    |> put_field("config_object_template", config["object_template"])
    |> put_field("config_format", config["format"])
    |> put_field("config_compression", config["compression"])
    |> put_field("config_max_records", config["max_records"])
    |> put_field("config_max_mb", bytes_to_mb(config["max_bytes"]))
    |> put_field("config_max_interval_seconds", config["max_interval_seconds"])
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

  defp config_form_params("slack", config) do
    # webhook_url and bot_token are secret — left blank on edit.
    %{}
    |> put_field("config_auth_mode", config["auth_mode"])
    |> put_field("config_channel", config["channel"])
    |> put_field("config_username", config["username"])
    |> put_field("config_icon_emoji", config["icon_emoji"])
    |> put_field("config_message_template", config["message_template"])
    |> put_field("config_blocks_template", config["blocks_template"])
  end

  defp config_form_params("dynamodb", config) do
    # secret_access_key and session_token are secret — left blank on edit.
    %{}
    |> put_field("config_table_name", config["table_name"])
    |> put_field("config_partition_key", config["partition_key"])
    |> put_field("config_sort_key", config["sort_key"])
    |> put_field("config_region", config["region"])
    |> put_field("config_endpoint", config["endpoint"])
    |> put_field("config_auth_mode", config["auth_mode"])
    |> put_field("config_access_key_id", config["access_key_id"])
    |> put_field("config_role_arn", config["role_arn"])
    |> put_field("config_external_id", config["external_id"])
    |> put_field("config_write_mode", config["write_mode"])
    |> put_field("config_version_attribute", config["version_attribute"])
    |> put_field("config_ttl_attribute", config["ttl_attribute"])
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

  defp build_config(params, "parquet") do
    # Optional fields that can be cleared are always written (as nil / ""), so
    # clearing them on edit isn't undone by merge_config_params/3.
    # Unparseable schema JSON is passed through as the raw string so
    # validate_config/1 rejects it, rather than silently falling back to inference.
    schema =
      case String.trim(params["config_schema"] || "") do
        "" ->
          nil

        raw ->
          case Jason.decode(raw) do
            {:ok, map} when map == %{} -> nil
            {:ok, map} when is_map(map) -> map
            _ -> raw
          end
      end

    %{}
    |> maybe_put("directory", params["config_directory"])
    |> maybe_put("compression", params["config_compression"])
    |> maybe_put("schema_mode", params["config_schema_mode"])
    |> Map.put("path_template", blank_to_nil(params["config_path_template"]))
    |> Map.put("partition_template", params["config_partition_template"] || "")
    |> Map.put("compression_level", parse_int(params["config_compression_level"]))
    |> Map.put("max_rows", parse_int(params["config_max_rows"]))
    |> Map.put("max_interval_seconds", parse_int(params["config_max_interval_seconds"]))
    |> Map.put("schema", schema)
  end

  # Non-secret fields always take the form's value, so clearing one (a body, the
  # Reply-To, a rate limit) removes it rather than the saved value creeping
  # back in through merge_config_params/3. Only the secrets keep "blank means
  # unchanged", because they are never echoed into the form.
  defp build_config(params, "email") do
    rate_limit =
      %{}
      |> maybe_put("max_per_minute", parse_int(params["config_max_per_minute"]))
      |> maybe_put("max_wait_ms", parse_int(params["config_max_wait_ms"]))

    %{}
    |> Map.put("provider", blank_to_nil(params["config_provider"]) || "smtp")
    |> put_clearable("host", params["config_host"])
    |> Map.put("port", parse_int(params["config_port"]))
    |> put_clearable("security", params["config_security"])
    |> put_clearable("username", params["config_username"])
    |> maybe_put("password", params["config_password"])
    |> Map.put("tls_verify", params["config_tls_skip_verify"] != "true")
    |> maybe_put("api_key", trim(params["config_api_key"]))
    |> put_clearable("domain", params["config_domain"])
    |> put_clearable("region", params["config_region"])
    |> put_clearable("access_key", params["config_access_key"])
    |> maybe_put("secret_access_key", trim(params["config_secret_access_key"]))
    |> put_clearable("from", params["config_from"])
    |> put_clearable("from_name", params["config_from_name"])
    |> put_clearable("reply_to", params["config_reply_to"])
    |> Map.put("to", address_list(params["config_to"]))
    |> Map.put("cc", address_list(params["config_cc"]))
    |> Map.put("bcc", address_list(params["config_bcc"]))
    |> put_clearable("subject", params["config_subject"], trim: false)
    |> put_clearable("html_body", params["config_html_body"], trim: false)
    |> put_clearable("text_body", params["config_text_body"], trim: false)
    |> Map.put("rate_limit", if(rate_limit == %{}, do: nil, else: rate_limit))
  end

  defp build_config(params, "bigquery") do
    %{}
    |> maybe_put("project_id", params["config_project_id"])
    |> maybe_put("dataset", params["config_dataset"])
    |> maybe_put("table", params["config_table"])
    |> maybe_put("credentials", params["config_credentials"])
    |> maybe_put("location", params["config_location"])
  end

  # Optional fields that can be cleared are always written (as nil), so clearing
  # them on edit isn't undone by merge_config_params/3. Only the secret keeps
  # "blank means unchanged".
  defp build_config(params, "gcs") do
    %{}
    |> maybe_put("bucket", params["config_bucket"])
    |> maybe_put("credentials", params["config_credentials"])
    |> maybe_put("format", params["config_format"])
    |> maybe_put("compression", params["config_compression"])
    |> put_clearable("object_template", params["config_object_template"])
    |> Map.put("max_records", parse_int(params["config_max_records"]))
    |> Map.put("max_bytes", mb_to_bytes(parse_int(params["config_max_mb"])))
    |> Map.put("max_interval_seconds", parse_int(params["config_max_interval_seconds"]))
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

  defp build_config(params, "slack") do
    %{}
    |> maybe_put("auth_mode", params["config_auth_mode"])
    |> maybe_put("webhook_url", params["config_webhook_url"])
    |> maybe_put("bot_token", params["config_bot_token"])
    |> maybe_put("channel", params["config_channel"])
    |> maybe_put("username", params["config_username"])
    |> maybe_put("icon_emoji", params["config_icon_emoji"])
    |> maybe_put("message_template", params["config_message_template"])
    |> maybe_put("blocks_template", params["config_blocks_template"])
  end

  # Settings are clearable (a blank field removes the stored value), and a
  # mode-specific field is cleared whenever its mode isn't selected, whatever
  # the submitted form still held. Only the secrets keep "blank means
  # unchanged" — see carried_config/3.
  defp build_config(params, "dynamodb") do
    auth_mode = params["config_auth_mode"]
    if_newer? = params["config_write_mode"] == "if_newer"

    %{}
    |> put_clearable("table_name", params["config_table_name"])
    |> put_clearable("partition_key", params["config_partition_key"])
    |> put_clearable("sort_key", params["config_sort_key"])
    |> put_clearable("region", params["config_region"])
    |> put_clearable("endpoint", params["config_endpoint"])
    |> maybe_put("auth_mode", auth_mode)
    |> put_clearable(
      "access_key_id",
      if(auth_mode == "static", do: params["config_access_key_id"])
    )
    |> maybe_put("secret_access_key", trim(params["config_secret_access_key"]))
    |> put_session_token(params)
    |> put_clearable("role_arn", if(auth_mode == "assume_role", do: params["config_role_arn"]))
    |> put_clearable(
      "external_id",
      if(auth_mode == "assume_role", do: params["config_external_id"])
    )
    |> maybe_put("write_mode", params["config_write_mode"])
    |> put_clearable("version_attribute", if(if_newer?, do: params["config_version_attribute"]))
    |> put_clearable("ttl_attribute", params["config_ttl_attribute"])
    |> Map.put("ttl_seconds", parse_int(params["config_ttl_seconds"]))
  end

  defp build_config(_params, _type), do: %{}

  # A new token wins; otherwise the "remove" checkbox clears the stored one (nil
  # overrides it in merge_config_params/3); otherwise it is left unchanged.
  defp put_session_token(map, params) do
    case {trim(params["config_session_token"]), params["config_clear_session_token"]} do
      {token, _} when token not in [nil, ""] -> Map.put(map, "session_token", token)
      {_, "true"} -> Map.put(map, "session_token", nil)
      _ -> map
    end
  end

  defp stored_session_token?(%Sink{type: "dynamodb", config: %{"session_token" => token}}),
    do: is_binary(token) and token != ""

  defp stored_session_token?(_sink), do: false

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  # Valid addresses are stored normalized; an invalid entry is kept verbatim so
  # the adapter's validation reports it by name instead of it silently vanishing.
  defp address_list(nil), do: []

  defp address_list(value) when is_binary(value) do
    case Flux.EmailAddress.validate_list(value) do
      {:ok, addresses} -> addresses
      {:error, _} -> Flux.EmailAddress.split_list(value)
    end
  end

  # Stored recipients are normally a list, but the adapter also accepts a
  # comma-separated string (e.g. a sink created through the API).
  defp join_addresses(list) when is_list(list) and list != [], do: Enum.join(list, ", ")
  defp join_addresses(value) when is_binary(value), do: blank_to_nil(value)
  defp join_addresses(_), do: nil

  defp recipient_fields do
    [
      {:config_to, "To", true},
      {:config_cc, "Cc (optional)", false},
      {:config_bcc, "Bcc (optional)", false}
    ]
  end

  # Per-address problems for a recipient field, shown live under the textarea
  # as the user types (the changeset only carries them as one :config error).
  defp recipient_errors(form, field) do
    case form.params[Atom.to_string(field)] do
      value when is_binary(value) and value != "" ->
        case Flux.EmailAddress.validate_list(value) do
          {:ok, _} -> []
          {:error, messages} -> messages
        end

      _ ->
        []
    end
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value

  # Puts the field even when blank (as nil), so it overrides the stored value.
  defp put_clearable(map, key, value, opts \\ []) do
    value = if Keyword.get(opts, :trim, true), do: trim(value), else: value
    Map.put(map, key, blank_to_nil(value))
  end

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

  @mb 1024 * 1024

  defp mb_to_bytes(mb) when is_integer(mb), do: mb * @mb
  defp mb_to_bytes(_), do: nil

  defp bytes_to_mb(bytes) when is_integer(bytes) and bytes > 0, do: max(div(bytes, @mb), 1)
  defp bytes_to_mb(_), do: nil

  defp gcs_compression_options("parquet") do
    [{"Snappy (default)", "snappy"}, {"Zstandard", "zstd"}, {"Gzip", "gzip"}, {"None", "none"}]
  end

  defp gcs_compression_options(_ndjson), do: [{"Gzip (default)", "gzip"}, {"None", "none"}]

  # A Pro sink type is "locked" when the current license isn't entitled to it.
  # Community always returns false from entitled?/1, so the upgrade prompt shows;
  # a licensed EE build resolves to true and the config fields render.
  # Current value of a virtual `config_*` field from the live form params, used
  # to drive the dynamic `*` marker on mode-dependent required fields. The form
  # re-renders on `phx-change="validate"`, so params hold the latest selection.
  defp cfg(form, key), do: form.params[key]

  defp pro_locked?(type) do
    case Map.fetch(@pro_sink_features, type) do
      {:ok, feature} -> not Flux.License.entitled?(feature)
      :error -> false
    end
  end

  defp type_option(type), do: Enum.find(@sink_type_options, &(&1.type == type))

  # Why the submit button is disabled, or nil when the form can be submitted.
  defp submit_hint(nil), do: "Choose a destination to continue"

  defp submit_hint(type) do
    if pro_locked?(type),
      do: "#{pro_label(type)} need Flux Pro, so this sink can't be created yet"
  end

  defp to_sentence([only]), do: only

  defp to_sentence(items) do
    {init, [last]} = Enum.split(items, -1)
    Enum.join(init, ", ") <> " and " <> last
  end

  defp pro_label("s3"), do: "S3 sinks"
  defp pro_label("bigquery"), do: "BigQuery sinks"
  defp pro_label("kafka"), do: "Kafka sinks"
  defp pro_label("snowflake"), do: "Snowflake sinks"
  defp pro_label("redis"), do: "Redis sinks"
  defp pro_label("mongodb"), do: "MongoDB sinks"
  defp pro_label("slack"), do: "Slack sinks"
  defp pro_label("dynamodb"), do: "DynamoDB sinks"
  defp pro_label("gcs"), do: "Google Cloud Storage sinks"
  defp pro_label(type), do: "#{type} sinks"
end
