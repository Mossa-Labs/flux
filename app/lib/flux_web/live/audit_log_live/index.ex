defmodule FluxWeb.AuditLogLive.Index do
  @moduledoc """
  Owner-only, Enterprise-gated audit log viewer (MOS-482).

  Paginated, filterable table of audit entries (who did what, when, from where),
  with an expandable row that reveals the JSON change diff. Data is served by the
  active `Flux.Audit.Provider`: the Community build has no audit store and
  surfaces an upgrade prompt; the Enterprise build serves Postgres-backed rows.
  Non-owners get a 403 with a redirect back to the dashboard.
  """
  use FluxWeb, :live_view

  alias Flux.Audit
  alias Flux.Audit.Event
  alias FluxWeb.Components.UpgradePrompt

  @per_page 25
  @redirect_after_ms 20_000
  @tick_ms 1_000

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    authorized? = scope && Flux.Permissions.can?(scope, :view_audit_log)
    entitled? = Flux.License.has_feature?(:audit_log)

    cond do
      not authorized? ->
        Process.send_after(self(), :redirect_to_dashboard, @redirect_after_ms)
        Process.send_after(self(), :tick, @tick_ms)

        {:ok,
         socket
         |> assign(:active_tab, :audit_log)
         |> assign(:page_title, "Forbidden")
         |> assign(:authorized, false)
         |> assign(:seconds_left, 20)}

      true ->
        {:ok, socket |> base_assigns(entitled?: entitled?) |> load_logs()}
    end
  end

  defp base_assigns(socket, entitled?: entitled?) do
    socket
    |> assign(:active_tab, :audit_log)
    |> assign(:page_title, "Audit Log")
    |> assign(:authorized, true)
    |> assign(:audit_entitled, entitled?)
    |> assign(:entries, [])
    |> assign(:total, 0)
    |> assign(:page, 0)
    |> assign(:per_page, @per_page)
    |> assign(:expanded_id, nil)
    |> assign(:filters, %{})
    |> assign(:actions, Enum.map(Event.actions(), &to_string/1))
    |> assign(:resource_types, resource_types())
  end

  # -- Events --

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    {:noreply,
     socket
     |> assign(:filters, prune_filters(filters))
     |> assign(:page, 0)
     |> load_logs()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, socket |> assign(:filters, %{}) |> assign(:page, 0) |> load_logs()}
  end

  def handle_event("toggle_expand", %{"id" => id}, socket) do
    expanded = if socket.assigns.expanded_id == id, do: nil, else: id
    {:noreply, assign(socket, :expanded_id, expanded)}
  end

  def handle_event("prev_page", _params, socket) do
    page = max(socket.assigns.page - 1, 0)
    {:noreply, socket |> assign(:page, page) |> load_logs()}
  end

  def handle_event("next_page", _params, socket) do
    {:noreply, socket |> assign(:page, socket.assigns.page + 1) |> load_logs()}
  end

  @impl true
  def handle_info(:tick, %{assigns: %{authorized: false, seconds_left: n}} = socket)
      when n > 0 do
    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, assign(socket, :seconds_left, n - 1)}
  end

  def handle_info(:tick, socket), do: {:noreply, socket}

  def handle_info(:redirect_to_dashboard, socket) do
    {:noreply, push_navigate(socket, to: ~p"/dashboard")}
  end

  # -- Data loading --

  defp load_logs(%{assigns: %{audit_entitled: true}} = socket) do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id
    filters = build_filters(socket.assigns.filters)
    page = socket.assigns.page

    entries =
      Audit.list_logs(org_id, filters: filters, limit: @per_page, offset: page * @per_page)

    assign(socket, entries: entries, total: Audit.count(org_id, filters))
  end

  defp load_logs(socket), do: assign(socket, entries: [], total: 0)

  # -- Render --

  @impl true
  def render(%{authorized: false} = assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-24 text-center">
      <div class="p-4 bg-error/10 rounded-full mb-4">
        <.icon name="hero-lock-closed" class="w-12 h-12 text-error" />
      </div>
      <h1 class="text-2xl font-bold text-base-content">403 Forbidden</h1>
      <p class="text-base-content/60 mt-2 max-w-md">
        The audit log is restricted to organization owners.
        Redirecting to your dashboard in {@seconds_left}s.
      </p>
      <.link navigate={~p"/dashboard"} class="btn btn-primary mt-6">Back to dashboard</.link>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div>
          <h1 class="text-2xl font-bold tracking-tight text-base-content">Audit Log</h1>
          <p class="text-base-content/60 mt-1">
            Who did what, when, and from where across your organization
          </p>
        </div>
        <div :if={@audit_entitled && @entries != []} class="flex items-center gap-2">
          <.link href={export_path(@filters, "csv")} class="btn btn-sm btn-outline">
            <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> CSV
          </.link>
          <.link href={export_path(@filters, "json")} class="btn btn-sm btn-outline">
            <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> JSON
          </.link>
        </div>
      </div>

      <UpgradePrompt.upgrade_prompt :if={!@audit_entitled} feature={:audit_log} />

      <%!-- Filter bar --%>
      <.form
        :if={@audit_entitled}
        for={%{}}
        as={:filters}
        id="audit-filters"
        phx-change="filter"
        phx-submit="filter"
        class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-5"
      >
        <input
          type="text"
          name="filters[actor_id]"
          value={@filters["actor_id"]}
          placeholder="Actor ID"
          class="input input-sm input-bordered w-full"
        />
        <select name="filters[action]" class="select select-sm select-bordered w-full">
          <option value="">All actions</option>
          <option :for={action <- @actions} value={action} selected={@filters["action"] == action}>
            {action}
          </option>
        </select>
        <select name="filters[resource_type]" class="select select-sm select-bordered w-full">
          <option value="">All resources</option>
          <option
            :for={type <- @resource_types}
            value={type}
            selected={@filters["resource_type"] == type}
          >
            {type}
          </option>
        </select>
        <input
          type="datetime-local"
          name="filters[from]"
          value={@filters["from"]}
          class="input input-sm input-bordered w-full"
        />
        <input
          type="datetime-local"
          name="filters[to]"
          value={@filters["to"]}
          class="input input-sm input-bordered w-full"
        />
      </.form>

      <div :if={@audit_entitled && @filters != %{}} class="flex justify-end">
        <button class="btn btn-ghost btn-xs" phx-click="clear_filters">Clear filters</button>
      </div>

      <%!-- Table --%>
      <div :if={@audit_entitled} class="overflow-x-auto rounded-lg border border-base-200">
        <table class="table table-sm">
          <thead>
            <tr>
              <th></th>
              <th>Time</th>
              <th>Actor</th>
              <th>Action</th>
              <th>Resource</th>
              <th>IP</th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@entries == []}>
              <td colspan="6" class="text-center text-base-content/50 py-8">
                No audit entries match the current filters.
              </td>
            </tr>
            <%= for entry <- @entries do %>
              <tr id={"audit-row-#{entry.id}"} class="hover">
                <td>
                  <button
                    :if={has_changes?(entry)}
                    phx-click="toggle_expand"
                    phx-value-id={to_string(entry.id)}
                    class="btn btn-ghost btn-xs"
                  >
                    <.icon
                      name={
                        if @expanded_id == to_string(entry.id),
                          do: "hero-chevron-down",
                          else: "hero-chevron-right"
                      }
                      class="w-4 h-4"
                    />
                  </button>
                </td>
                <td class="whitespace-nowrap font-mono text-xs">
                  {format_timestamp(entry.inserted_at)}
                </td>
                <td class="whitespace-nowrap">
                  <span class="badge badge-ghost badge-sm">{entry.actor_type}</span>
                  <span class="ml-1 font-mono text-xs">{entry.actor_id || "—"}</span>
                </td>
                <td><span class="badge badge-sm">{entry.action}</span></td>
                <td class="whitespace-nowrap text-xs">
                  {entry.resource_type}<span :if={entry.resource_id} class="text-base-content/50">#{entry.resource_id}</span>
                </td>
                <td class="font-mono text-xs">{ip_of(entry)}</td>
              </tr>
              <tr
                :if={@expanded_id == to_string(entry.id) && has_changes?(entry)}
                id={"audit-json-#{entry.id}"}
              >
                <td colspan="6" class="bg-base-200/30">
                  <pre class="text-xs overflow-x-auto whitespace-pre-wrap break-all">{full_json(entry.changes)}</pre>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <%!-- Pagination --%>
      <div :if={@audit_entitled && @total > 0} class="flex items-center justify-between">
        <span class="text-sm text-base-content/60">
          Showing {@page * @per_page + 1}–{min((@page + 1) * @per_page, @total)} of {@total}
        </span>
        <div class="join">
          <button class="btn btn-sm join-item" phx-click="prev_page" disabled={@page == 0}>
            Previous
          </button>
          <button class="btn btn-sm join-item btn-disabled">Page {@page + 1}</button>
          <button
            class="btn btn-sm join-item"
            phx-click="next_page"
            disabled={(@page + 1) * @per_page >= @total}
          >
            Next
          </button>
        </div>
      </div>
    </div>
    """
  end

  # -- Filters --

  # Convert the flat UI filter map into the provider's atom-keyed filter map,
  # parsing datetime-local inputs to UTC DateTimes.
  defp build_filters(filters) do
    %{}
    |> put_present(:actor_id, filters["actor_id"])
    |> put_present(:action, filters["action"])
    |> put_present(:resource_type, filters["resource_type"])
    |> put_present(:from, parse_dt(filters["from"]))
    |> put_present(:to, parse_dt(filters["to"]))
  end

  defp put_present(map, _key, value) when value in [nil, ""], do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp prune_filters(filters) do
    filters
    |> Enum.reject(fn {_k, v} -> blank?(v) end)
    |> Map.new()
  end

  defp export_path(filters, format) do
    query = filters |> Map.put("format", format) |> URI.encode_query()
    ~p"/system/audit-logs/export" <> "?" <> query
  end

  # datetime-local inputs are `YYYY-MM-DDTHH:MM[:SS]`, naive; treat as UTC.
  defp parse_dt(value) do
    if blank?(value) do
      nil
    else
      case NaiveDateTime.from_iso8601(pad_seconds(value)) do
        {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
        _ -> nil
      end
    end
  end

  defp pad_seconds(str) do
    case String.split(str, ":") do
      [_h, _m] -> str <> ":00"
      _ -> str
    end
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false

  # -- Formatting --

  defp resource_types do
    ~w(pipeline sink organization organization_member team team_member api_key user)
  end

  defp has_changes?(%{changes: changes}) when is_map(changes), do: map_size(changes) > 0
  defp has_changes?(_), do: false

  defp ip_of(%{metadata: %{"ip_address" => ip}}) when is_binary(ip), do: ip
  defp ip_of(_), do: "—"

  defp format_timestamp(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  defp format_timestamp(_), do: "—"

  defp full_json(changes) do
    Jason.encode!(changes, pretty: true)
  rescue
    _ -> inspect(changes, pretty: true)
  end
end
