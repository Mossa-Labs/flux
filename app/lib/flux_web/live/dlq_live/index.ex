defmodule FluxWeb.DLQLive.Index do
  @moduledoc """
  Owner-only, Pro-gated dead-letter queue management.

  Inspect failed messages, replay them to their original queue, or discard
  them. Real data is served by the active queue adapter's DLQ callbacks
  (EE RabbitMQ/Kafka); Community/Memory builds surface an upgrade prompt.
  Non-owners get a 403 with a redirect back to the dashboard.
  """
  use FluxWeb, :live_view

  alias Flux.Pipelines
  alias Flux.Queue
  alias Flux.Queue.Replay
  alias FluxWeb.Components.UpgradePrompt

  @refresh_interval_ms 10_000
  @per_page 25
  @redirect_after_ms 20_000
  @tick_ms 1_000

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    authorized? = scope && Flux.Permissions.can?(scope, :view_system_settings)
    entitled? = Flux.License.has_feature?(:dlq)

    cond do
      not authorized? ->
        Process.send_after(self(), :redirect_to_dashboard, @redirect_after_ms)
        Process.send_after(self(), :tick, @tick_ms)

        {:ok,
         socket
         |> assign(:active_tab, :system_settings)
         |> assign(:page_title, "Forbidden")
         |> assign(:authorized, false)
         |> assign(:seconds_left, 20)}

      entitled? ->
        if connected?(socket) do
          :timer.send_interval(@refresh_interval_ms, self(), :refresh)
        end

        {:ok,
         socket
         |> base_assigns(entitled?: true)
         |> assign(:pipelines, list_pipelines(scope))
         |> load_dlq()}

      true ->
        {:ok, base_assigns(socket, entitled?: false)}
    end
  end

  defp base_assigns(socket, entitled?: entitled?) do
    socket
    |> assign(:active_tab, :system_settings)
    |> assign(:page_title, "Dead Letter Queue")
    |> assign(:authorized, true)
    |> assign(:dlq_entitled, entitled?)
    |> assign(:depth, 0)
    |> assign(:messages, [])
    |> assign(:page, 0)
    |> assign(:expanded_tag, nil)
    |> assign(:loading, entitled?)
    |> assign(:unsupported, false)
    |> assign(:per_page, @per_page)
    |> assign(:filters, %{})
    |> assign(:pipelines, [])
    |> assign(:selected, MapSet.new())
    |> assign(:replay_job_id, nil)
    |> assign(:replay_progress, nil)
  end

  defp list_pipelines(%{organization_id: org_id}) when not is_nil(org_id) do
    Pipelines.list_pipelines(org_id)
  rescue
    _ -> []
  end

  defp list_pipelines(_), do: []

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_dlq(socket)}
  end

  def handle_info(:redirect_to_dashboard, socket) do
    {:noreply, redirect(socket, to: ~p"/dashboard")}
  end

  def handle_info(:tick, socket) do
    if socket.assigns.authorized do
      {:noreply, socket}
    else
      secs = socket.assigns.seconds_left

      if secs <= 1 do
        {:noreply, redirect(socket, to: ~p"/dashboard")}
      else
        Process.send_after(self(), :tick, @tick_ms)
        {:noreply, assign(socket, :seconds_left, secs - 1)}
      end
    end
  end

  def handle_info({:replay_progress, progress}, socket) do
    {:noreply, assign(socket, :replay_progress, progress)}
  end

  def handle_info({:replay_done, progress}, socket) do
    {:noreply,
     socket
     |> assign(:replay_progress, progress)
     |> assign(:replay_job_id, nil)
     |> assign(:selected, MapSet.new())
     |> put_flash(
       :info,
       "Replay finished: #{progress.processed} replayed, #{progress.skipped} skipped, #{progress.failed} failed."
     )
     |> load_dlq()}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle_expand", %{"tag" => tag}, socket) do
    expanded = if socket.assigns.expanded_tag == tag, do: nil, else: tag
    {:noreply, assign(socket, :expanded_tag, expanded)}
  end

  def handle_event("retry", %{"tag" => tag}, socket) do
    case find_tag(socket.assigns.messages, tag) do
      nil ->
        {:noreply, socket}

      delivery_tag ->
        {:noreply,
         run_dlq_op(
           socket,
           &Queue.retry_message/1,
           delivery_tag,
           "Message replayed to its original queue."
         )}
    end
  end

  def handle_event("discard", %{"tag" => tag}, socket) do
    case find_tag(socket.assigns.messages, tag) do
      nil ->
        {:noreply, socket}

      delivery_tag ->
        {:noreply,
         run_dlq_op(socket, &Queue.discard_message/1, delivery_tag, "Message discarded.")}
    end
  end

  def handle_event("retry_all", _params, socket) do
    {:noreply, run_dlq_bulk(socket, &Queue.retry_message/1, "Replayed")}
  end

  def handle_event("discard_all", _params, socket) do
    {:noreply, run_dlq_bulk(socket, &Queue.discard_message/1, "Discarded")}
  end

  def handle_event("filter", %{"filters" => filters}, socket) do
    {:noreply,
     socket
     |> assign(:filters, prune_filters(filters))
     |> assign(:page, 0)
     |> assign(:selected, MapSet.new())
     |> load_dlq()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:filters, %{})
     |> assign(:page, 0)
     |> assign(:selected, MapSet.new())
     |> load_dlq()}
  end

  def handle_event("toggle_select", %{"tag" => tag}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected, tag) do
        MapSet.delete(socket.assigns.selected, tag)
      else
        MapSet.put(socket.assigns.selected, tag)
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("replay_selected", _params, socket) do
    delivery_tags =
      socket.assigns.messages
      |> Enum.filter(&MapSet.member?(socket.assigns.selected, to_string(&1.delivery_tag)))
      |> Enum.map(& &1.delivery_tag)

    {ok, failed} =
      Enum.reduce(delivery_tags, {0, 0}, fn tag, {ok, failed} ->
        case Queue.retry_message(tag) do
          :ok -> {ok + 1, failed}
          {:error, _} -> {ok, failed + 1}
        end
      end)

    socket = socket |> assign(:selected, MapSet.new()) |> load_dlq()

    socket =
      if failed == 0 do
        put_flash(socket, :info, "Replayed #{ok} selected message(s).")
      else
        put_flash(socket, :error, "Replayed #{ok} message(s); #{failed} failed.")
      end

    {:noreply, socket}
  end

  def handle_event("replay_all_filtered", _params, socket) do
    scope = socket.assigns.current_scope

    replay_filters = to_replay_filters(socket.assigns.filters)

    case Replay.replay_messages(replay_filters, organization_id: scope.organization_id) do
      {:ok, %Oban.Job{id: job_id}} ->
        if connected?(socket), do: Phoenix.PubSub.subscribe(Flux.PubSub, Replay.topic(job_id))

        {:noreply,
         socket
         |> assign(:replay_job_id, job_id)
         |> assign(:replay_progress, Replay.zero_progress())
         |> put_flash(:info, "Bulk replay started.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not start replay: #{inspect(reason)}")}
    end
  end

  def handle_event("prev_page", _params, socket) do
    page = max(socket.assigns.page - 1, 0)
    {:noreply, socket |> assign(:page, page) |> load_dlq()}
  end

  def handle_event("next_page", _params, socket) do
    {:noreply, socket |> assign(:page, socket.assigns.page + 1) |> load_dlq()}
  end

  # -- Data loading --

  defp load_dlq(%{assigns: %{dlq_entitled: true}} = socket) do
    page = socket.assigns.page

    socket =
      case Queue.dlq_depth() do
        {:ok, depth} -> socket |> assign(:depth, depth) |> assign(:unsupported, false)
        {:error, {:pro_required, :dlq}} -> assign(socket, :unsupported, true)
        {:error, _} -> socket
      end

    socket =
      case Queue.list_dlq_messages(@per_page, page * @per_page) do
        {:ok, messages} ->
          assign(
            socket,
            :messages,
            filter_messages(messages, socket.assigns.filters, socket.assigns.pipelines)
          )

        {:error, _} ->
          assign(socket, :messages, [])
      end

    assign(socket, :loading, false)
  end

  defp load_dlq(socket), do: socket

  defp run_dlq_op(socket, op, delivery_tag, success_msg) do
    case op.(delivery_tag) do
      :ok ->
        socket |> put_flash(:info, success_msg) |> load_dlq()

      {:error, reason} ->
        put_flash(socket, :error, "Operation failed: #{inspect(reason)}")
    end
  end

  defp run_dlq_bulk(socket, op, verb) do
    {ok, failed} =
      socket.assigns.messages
      |> Enum.reduce({0, 0}, fn msg, {ok, failed} ->
        case op.(msg.delivery_tag) do
          :ok -> {ok + 1, failed}
          {:error, _} -> {ok, failed + 1}
        end
      end)

    socket = load_dlq(socket)

    if failed == 0 do
      put_flash(socket, :info, "#{verb} #{ok} message(s).")
    else
      put_flash(socket, :error, "#{verb} #{ok} message(s); #{failed} failed.")
    end
  end

  # Recover the original (type-agnostic) delivery_tag term from its string form.
  defp find_tag(messages, tag_string) do
    Enum.find_value(messages, fn msg ->
      if to_string(msg.delivery_tag) == tag_string, do: msg.delivery_tag
    end)
  end

  @impl true
  def render(%{authorized: false} = assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-24 text-center">
      <div class="p-4 bg-error/10 rounded-full mb-4">
        <.icon name="hero-lock-closed" class="w-12 h-12 text-error" />
      </div>
      <h1 class="text-2xl font-bold text-base-content">403 Forbidden</h1>
      <p class="text-base-content/60 mt-2 max-w-md">
        Dead-letter queue management is restricted to organization owners.
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
          <h1 class="text-2xl font-bold tracking-tight text-base-content">
            Dead Letter Queue
          </h1>
          <p class="text-base-content/60 mt-1">Inspect, replay, or discard failed messages</p>
        </div>
        <div
          :if={@dlq_entitled && !@unsupported && @messages != []}
          class="flex flex-wrap items-center gap-2"
        >
          <button
            :if={MapSet.size(@selected) > 0}
            class="btn btn-sm btn-primary"
            phx-click="replay_selected"
          >
            <.icon name="hero-arrow-uturn-left" class="w-4 h-4" />
            Replay selected ({MapSet.size(@selected)})
          </button>
          <button
            class="btn btn-sm btn-outline"
            phx-click="replay_all_filtered"
            disabled={@replay_job_id != nil}
            data-confirm="Replay every dead-lettered message matching the current filters back to its original queue?"
          >
            <.icon name="hero-arrow-path" class="w-4 h-4" /> Replay all (filtered)
          </button>
          <button
            class="btn btn-sm btn-outline"
            phx-click="retry_all"
            data-confirm="Replay all messages on this page back to their original queues?"
          >
            <.icon name="hero-arrow-path" class="w-4 h-4" /> Retry page
          </button>
          <button
            class="btn btn-sm btn-outline btn-error"
            phx-click="discard_all"
            data-confirm="Permanently discard all messages on this page? This cannot be undone."
          >
            <.icon name="hero-trash" class="w-4 h-4" /> Discard page
          </button>
        </div>
      </div>

      <UpgradePrompt.upgrade_prompt :if={!@dlq_entitled} feature={:dlq} />

      <div
        :if={@dlq_entitled && @unsupported}
        class="rounded-lg border border-amber-300 bg-amber-50 p-4 text-sm text-amber-900"
      >
        The active queue backend does not support dead-letter management.
        Configure a Pro broker (RabbitMQ) to enable it.
      </div>

      <%!-- Filter bar --%>
      <.form
        :if={@dlq_entitled && !@unsupported}
        for={%{}}
        as={:filters}
        id="dlq-filters"
        phx-change="filter"
        phx-submit="filter"
        class="card bg-base-100 shadow-sm border border-base-200"
      >
        <div class="card-body p-4 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-3 items-end">
          <label class="form-control">
            <span class="label-text text-xs">Original queue</span>
            <input
              type="text"
              name="filters[queue]"
              value={@filters["queue"]}
              placeholder="any"
              class="input input-sm input-bordered"
            />
          </label>
          <label class="form-control">
            <span class="label-text text-xs">Source</span>
            <input
              type="text"
              name="filters[source]"
              value={@filters["source"]}
              placeholder="any"
              class="input input-sm input-bordered"
            />
          </label>
          <label class="form-control">
            <span class="label-text text-xs">Pipeline</span>
            <select name="filters[pipeline_id]" class="select select-sm select-bordered">
              <option value="">Any pipeline</option>
              <option
                :for={pipeline <- @pipelines}
                value={pipeline.id}
                selected={to_string(pipeline.id) == @filters["pipeline_id"]}
              >
                {pipeline.name}
              </option>
            </select>
          </label>
          <label class="form-control">
            <span class="label-text text-xs">From</span>
            <input
              type="datetime-local"
              name="filters[from]"
              value={@filters["from"]}
              class="input input-sm input-bordered"
            />
          </label>
          <label class="form-control">
            <span class="label-text text-xs">To</span>
            <input
              type="datetime-local"
              name="filters[to]"
              value={@filters["to"]}
              class="input input-sm input-bordered"
            />
          </label>
        </div>
        <div :if={@filters != %{}} class="px-4 pb-4 -mt-1">
          <button type="button" class="btn btn-xs btn-ghost" phx-click="clear_filters">
            <.icon name="hero-x-mark" class="w-3 h-3" /> Clear filters
          </button>
        </div>
      </.form>

      <%!-- Bulk replay progress --%>
      <div
        :if={@dlq_entitled && !@unsupported && @replay_progress != nil}
        id="dlq-replay-progress"
        class="card bg-base-100 shadow-sm border border-base-200"
      >
        <div class="card-body p-4 space-y-2">
          <div class="flex items-center justify-between text-sm">
            <span class="font-medium inline-flex items-center gap-2">
              <span :if={@replay_job_id != nil} class="loading loading-spinner loading-xs"></span>
              {if @replay_job_id != nil, do: "Replaying…", else: "Replay complete"}
            </span>
            <span class="text-base-content/60">
              {@replay_progress.processed} / {@replay_progress.total} replayed
              · {@replay_progress.skipped} skipped · {@replay_progress.failed} failed
            </span>
          </div>
          <progress
            class="progress progress-primary w-full"
            value={@replay_progress.processed}
            max={max(@replay_progress.total, 1)}
          >
          </progress>
        </div>
      </div>

      <%!-- Depth counter --%>
      <div
        :if={@dlq_entitled && !@unsupported}
        class="card bg-base-100 shadow-sm border border-base-200"
      >
        <div class="card-body p-4 flex-row items-center gap-3">
          <div class={[
            "p-2 rounded-lg",
            @depth > 0 && "bg-warning/10 text-warning",
            @depth == 0 && "bg-success/10 text-success"
          ]}>
            <.icon name="hero-inbox-stack" class="w-5 h-5" />
          </div>
          <div>
            <p class="text-2xl font-bold">{@depth}</p>
            <p class="text-sm text-base-content/60">Messages in dead-letter queue</p>
          </div>
        </div>
      </div>

      <%!-- Message list --%>
      <div
        :if={@dlq_entitled && !@unsupported}
        class="card bg-base-100 shadow-sm border border-base-200"
      >
        <div class="card-body p-0">
          <div
            :if={@loading}
            class="flex items-center justify-center py-16 text-base-content/40"
          >
            <span class="loading loading-spinner loading-md mr-2"></span> Loading messages…
          </div>

          <div
            :if={!@loading && @messages == []}
            class="flex flex-col items-center justify-center py-16 text-center"
          >
            <div class="p-4 bg-base-200 rounded-full mb-4">
              <.icon name="hero-check-circle" class="w-12 h-12 text-success/60" />
            </div>
            <h3 class="text-lg font-semibold">No dead-lettered messages</h3>
            <p class="text-base-content/60 mt-2 max-w-md">
              Failed messages that exhaust their retries will appear here for inspection.
            </p>
          </div>

          <div :if={!@loading && @messages != []} class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th class="w-8"></th>
                  <th>Original queue</th>
                  <th>Source</th>
                  <th>Failure reason</th>
                  <th>Timestamp</th>
                  <th>Payload</th>
                  <th class="text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                <%= for msg <- @messages do %>
                  <tr id={"dlq-row-#{msg.delivery_tag}"} class="hover">
                    <td>
                      <input
                        type="checkbox"
                        class="checkbox checkbox-sm"
                        phx-click="toggle_select"
                        phx-value-tag={to_string(msg.delivery_tag)}
                        checked={MapSet.member?(@selected, to_string(msg.delivery_tag))}
                      />
                    </td>
                    <td class="font-mono text-sm">{msg.original_queue || "—"}</td>
                    <td class="font-mono text-sm text-base-content/70">
                      {Map.get(msg, :source) || "—"}
                    </td>
                    <td class="text-sm text-error">{msg.reason || "—"}</td>
                    <td class="text-sm text-base-content/70">{format_timestamp(msg.timestamp)}</td>
                    <td>
                      <button
                        phx-click="toggle_expand"
                        phx-value-tag={to_string(msg.delivery_tag)}
                        class="font-mono text-xs text-base-content/60 hover:text-base-content max-w-xs truncate inline-flex items-center gap-1"
                      >
                        <.icon
                          name={
                            if @expanded_tag == to_string(msg.delivery_tag),
                              do: "hero-chevron-down",
                              else: "hero-chevron-right"
                          }
                          class="w-3 h-3 shrink-0"
                        />
                        {payload_preview(msg.payload)}
                      </button>
                    </td>
                    <td class="text-right whitespace-nowrap">
                      <button
                        class="btn btn-xs btn-ghost"
                        phx-click="retry"
                        phx-value-tag={to_string(msg.delivery_tag)}
                        data-confirm="Replay this message to its original queue?"
                      >
                        <.icon name="hero-arrow-path" class="w-4 h-4" /> Retry
                      </button>
                      <button
                        class="btn btn-xs btn-ghost text-error"
                        phx-click="discard"
                        phx-value-tag={to_string(msg.delivery_tag)}
                        data-confirm="Permanently discard this message? This cannot be undone."
                      >
                        <.icon name="hero-trash" class="w-4 h-4" /> Discard
                      </button>
                    </td>
                  </tr>
                  <tr
                    :if={@expanded_tag == to_string(msg.delivery_tag)}
                    id={"dlq-json-#{msg.delivery_tag}"}
                  >
                    <td colspan="7" class="bg-base-200/30">
                      <pre class="text-xs overflow-x-auto p-2 whitespace-pre-wrap break-all">{full_json(msg.payload)}</pre>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <%!-- Pagination --%>
          <div
            :if={!@loading && (@page > 0 || length(@messages) == @per_page)}
            class="flex items-center justify-between border-t border-base-200 p-3"
          >
            <button class="btn btn-sm btn-ghost" phx-click="prev_page" disabled={@page == 0}>
              <.icon name="hero-chevron-left" class="w-4 h-4" /> Previous
            </button>
            <span class="text-sm text-base-content/60">Page {@page + 1}</span>
            <button
              class="btn btn-sm btn-ghost"
              phx-click="next_page"
              disabled={length(@messages) < @per_page}
            >
              Next <.icon name="hero-chevron-right" class="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # -- Filtering helpers --

  # Drop blank inputs so the table/replay treat them as "no filter".
  defp prune_filters(filters) do
    filters
    |> Enum.reject(fn {_k, v} -> blank?(v) end)
    |> Map.new()
  end

  # Convert the flat UI filter map into the shape `Flux.Queue.Replay` expects:
  # `time_range` becomes a nested map of `DateTime`s (parsed as UTC).
  defp to_replay_filters(filters) do
    base = Map.take(filters, ["queue", "source", "pipeline_id"])
    from = parse_dt(filters["from"])
    to = parse_dt(filters["to"])

    if from && to do
      Map.put(base, "time_range", %{"from" => from, "to" => to})
    else
      base
    end
  end

  # In-memory filter applied to the current page for preview. The authoritative
  # whole-DLQ filtered replay runs in `Flux.Workers.ReplayWorker`.
  defp filter_messages(messages, filters, _pipelines) when filters == %{}, do: messages

  defp filter_messages(messages, filters, pipelines) do
    queue = effective_queue(filters, pipelines)
    source = filters["source"]
    from = parse_dt(filters["from"])
    to = parse_dt(filters["to"])

    Enum.filter(messages, fn msg ->
      queue_match?(msg, queue) and source_match?(msg, source) and time_match?(msg, from, to)
    end)
  end

  defp effective_queue(filters, pipelines) do
    case blank?(filters["pipeline_id"]) do
      true ->
        filters["queue"]

      false ->
        pid = filters["pipeline_id"]

        case Enum.find(pipelines, fn p -> to_string(p.id) == to_string(pid) end) do
          nil -> filters["queue"]
          pipeline -> pipeline.source_queue
        end
    end
  end

  defp queue_match?(_msg, nil), do: true
  defp queue_match?(msg, queue), do: Map.get(msg, :original_queue) == queue

  defp source_match?(_msg, nil), do: true
  defp source_match?(msg, source), do: Map.get(msg, :source) == source

  defp time_match?(_msg, nil, _to), do: true
  defp time_match?(_msg, _from, nil), do: true
  defp time_match?(%{timestamp: nil}, _from, _to), do: false

  defp time_match?(%{timestamp: ts}, from, to) do
    DateTime.compare(ts, from) != :lt and DateTime.compare(ts, to) != :gt
  end

  defp time_match?(_msg, _from, _to), do: false

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

  # -- Formatting helpers --

  defp format_timestamp(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_timestamp(_), do: "—"

  defp payload_preview(payload) do
    preview = payload |> Jason.encode!() |> String.slice(0, 80)
    if String.length(Jason.encode!(payload)) > 80, do: preview <> "…", else: preview
  rescue
    _ -> inspect(payload) |> String.slice(0, 80)
  end

  defp full_json(payload) do
    Jason.encode!(payload, pretty: true)
  rescue
    _ -> inspect(payload, pretty: true)
  end
end
