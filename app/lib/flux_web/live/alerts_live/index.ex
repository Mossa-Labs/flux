defmodule FluxWeb.AlertsLive.Index do
  @moduledoc """
  Owner-only, Pro-gated alerting & notifications (MOS-452).

  Create alert rules (anomaly / failure-rate / pipeline-stopped / DLQ-depth) with
  email, webhook, and Slack channels, toggle them, and review the fire history.
  Real data is served by the active `Flux.Alerts.Provider` (the Pro Postgres
  provider + a minute-by-minute evaluator); Community builds surface an upgrade
  prompt. Non-owners get a 403 with a redirect back to the dashboard.
  """
  use FluxWeb, :live_view

  alias Flux.Alerts
  alias FluxWeb.Components.UpgradePrompt

  @redirect_after_ms 20_000
  @tick_ms 1_000
  @default_cooldown 15

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    authorized? = scope && Flux.Permissions.can?(scope, :view_system_settings)
    entitled? = Flux.License.has_feature?(:alerting)

    cond do
      not authorized? ->
        Process.send_after(self(), :redirect_to_dashboard, @redirect_after_ms)
        Process.send_after(self(), :tick, @tick_ms)

        {:ok,
         socket
         |> assign(:active_tab, :alerts)
         |> assign(:page_title, "Forbidden")
         |> assign(:authorized, false)
         |> assign(:seconds_left, 20)}

      entitled? ->
        {:ok, socket |> base_assigns(entitled?: true) |> load_rules() |> reset_form()}

      true ->
        {:ok, base_assigns(socket, entitled?: false)}
    end
  end

  defp base_assigns(socket, entitled?: entitled?) do
    socket
    |> assign(:active_tab, :alerts)
    |> assign(:page_title, "Alerts")
    |> assign(:authorized, true)
    |> assign(:alerting_entitled, entitled?)
    |> assign(:rules, [])
    |> assign(:history, [])
    |> assign(:show_form, false)
    |> assign(:editing_id, nil)
    |> assign(:form, blank_form())
  end

  defp load_rules(%{assigns: %{alerting_entitled: true}} = socket) do
    org_id = socket.assigns.current_scope.organization_id

    socket
    |> assign(:rules, Alerts.list_rules(org_id))
    |> assign(:history, Alerts.list_history(org_id, limit: 50))
  end

  defp load_rules(socket), do: socket

  # -- Lifecycle messages (shared 403 countdown with DLQLive) --

  @impl true
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

  def handle_info(_msg, socket), do: {:noreply, socket}

  # -- Form events --

  @impl true
  def handle_event("new_rule", _params, socket) do
    {:noreply, socket |> assign(:show_form, true) |> assign(:editing_id, nil) |> reset_form()}
  end

  def handle_event("edit_rule", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.rules, &(to_string(&1.id) == id)) do
      nil ->
        {:noreply, socket}

      rule ->
        {:noreply,
         socket
         |> assign(:show_form, true)
         |> assign(:editing_id, rule.id)
         |> assign(:form, to_form(rule_to_params(rule), as: :rule))}
    end
  end

  def handle_event("cancel_form", _params, socket) do
    {:noreply, socket |> assign(:show_form, false) |> assign(:editing_id, nil) |> reset_form()}
  end

  def handle_event("validate", %{"rule" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :rule))}
  end

  def handle_event("save_rule", %{"rule" => params}, socket) do
    org_id = socket.assigns.current_scope.organization_id
    attrs = build_attrs(params)

    result =
      case socket.assigns.editing_id do
        nil -> Alerts.create_rule(org_id, attrs)
        id -> Alerts.update_rule(org_id, id, attrs)
      end

    case result do
      {:ok, _rule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Alert rule saved.")
         |> assign(:show_form, false)
         |> assign(:editing_id, nil)
         |> reset_form()
         |> load_rules()}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not save rule: #{format_error(reason)}")
         |> assign(:form, to_form(params, as: :rule))}
    end
  end

  def handle_event("toggle_rule", %{"id" => id, "enabled" => enabled}, socket) do
    org_id = socket.assigns.current_scope.organization_id

    case Alerts.toggle_rule(org_id, id, enabled in [true, "true", "on"]) do
      {:ok, _} -> {:noreply, load_rules(socket)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, format_error(reason))}
    end
  end

  def handle_event("delete_rule", %{"id" => id}, socket) do
    org_id = socket.assigns.current_scope.organization_id

    case Alerts.delete_rule(org_id, id) do
      :ok ->
        {:noreply, socket |> put_flash(:info, "Alert rule deleted.") |> load_rules()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, format_error(reason))}
    end
  end

  def handle_event("test_rule", %{"id" => id}, socket) do
    rule = Enum.find(socket.assigns.rules, &(to_string(&1.id) == id))

    socket =
      case rule do
        nil ->
          socket

        %{channels: []} ->
          put_flash(socket, :error, "This rule has no channels configured.")

        %{channels: channels} ->
          {ok, failed} =
            Enum.reduce(channels, {0, 0}, fn channel, {ok, failed} ->
              case Alerts.test_channel(channel) do
                :ok -> {ok + 1, failed}
                {:error, _} -> {ok, failed + 1}
              end
            end)

          if failed == 0 do
            put_flash(socket, :info, "Sent a test to #{ok} channel(s).")
          else
            put_flash(socket, :error, "#{ok} channel(s) delivered, #{failed} failed.")
          end
      end

    {:noreply, socket}
  end

  # -- Form helpers --

  defp reset_form(socket), do: assign(socket, :form, blank_form())

  defp blank_form do
    to_form(
      %{
        "name" => "",
        "trigger_type" => "anomaly",
        "threshold" => "",
        "cooldown_minutes" => Integer.to_string(@default_cooldown),
        "email_to" => "",
        "webhook_url" => "",
        "slack_url" => ""
      },
      as: :rule
    )
  end

  defp rule_to_params(rule) do
    channels = channel_map(rule.channels)

    %{
      "name" => rule.name,
      "trigger_type" => to_string(rule.trigger_type),
      "threshold" => threshold_string(rule.trigger_config),
      "cooldown_minutes" => Integer.to_string(rule.cooldown_minutes || @default_cooldown),
      "email_to" => get_in(channels, ["email", "to"]) || "",
      "webhook_url" => get_in(channels, ["webhook", "url"]) || "",
      "slack_url" => get_in(channels, ["slack", "url"]) || ""
    }
  end

  # %{"email" => %{"to" => ...}, "webhook" => %{"url" => ...}, ...}
  defp channel_map(channels) when is_list(channels) do
    Map.new(channels, fn ch -> {ch["type"] || ch[:type], ch["config"] || ch[:config] || %{}} end)
  end

  defp channel_map(_), do: %{}

  defp threshold_string(%{"threshold" => t}) when not is_nil(t), do: to_string(t)
  defp threshold_string(_), do: ""

  defp build_attrs(params) do
    %{
      "name" => String.trim(params["name"] || ""),
      "trigger_type" => params["trigger_type"],
      "trigger_config" => build_trigger_config(params),
      "channels" => build_channels(params),
      "cooldown_minutes" => parse_int(params["cooldown_minutes"], @default_cooldown)
    }
  end

  defp build_trigger_config(params) do
    case parse_number(params["threshold"]) do
      nil -> %{}
      n -> %{"threshold" => n}
    end
  end

  defp build_channels(params) do
    [
      channel("email", "to", params["email_to"]),
      channel("webhook", "url", params["webhook_url"]),
      channel("slack", "url", params["slack_url"])
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp channel(type, key, value) do
    case value && String.trim(value) do
      v when v in [nil, ""] -> nil
      v -> %{"type" => type, "config" => %{key => v}}
    end
  end

  defp parse_int(nil, default), do: default

  defp parse_int(value, default) do
    case Integer.parse(to_string(value)) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_number(nil), do: nil

  defp parse_number(value) do
    str = value |> to_string() |> String.trim()

    cond do
      str == "" -> nil
      match?({_, ""}, Integer.parse(str)) -> elem(Integer.parse(str), 0)
      match?({_, ""}, Float.parse(str)) -> elem(Float.parse(str), 0)
      true -> nil
    end
  end

  defp format_error(%Ecto.Changeset{} = cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
    |> Enum.map(fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
  end

  defp format_error({:pro_required, _}), do: "requires Flux Pro"
  defp format_error(reason), do: inspect(reason)

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
        Alerting is restricted to organization owners.
        Redirecting to your dashboard in {@seconds_left}s.
      </p>
      <.link navigate={~p"/dashboard"} class="btn btn-primary mt-6">Back to dashboard</.link>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-bold tracking-tight text-base-content">
            Alerts
          </h1>
          <p class="text-base-content/60 mt-1">
            Get notified when pipelines fail or anomalies are detected
          </p>
        </div>
        <button
          :if={@alerting_entitled && !@show_form}
          class="btn btn-sm btn-primary"
          phx-click="new_rule"
        >
          <.icon name="hero-plus" class="w-4 h-4" /> New rule
        </button>
      </div>

      <UpgradePrompt.upgrade_prompt :if={!@alerting_entitled} feature={:alerting} />

      <%!-- Rule form --%>
      <div
        :if={@alerting_entitled && @show_form}
        class="card bg-base-100 shadow-sm border border-base-200"
      >
        <div class="card-body">
          <h2 class="card-title text-base font-bold">
            {if @editing_id, do: "Edit alert rule", else: "New alert rule"}
          </h2>
          <.form for={@form} id="alert-rule-form" phx-change="validate" phx-submit="save_rule">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <.input
                field={@form[:name]}
                type="text"
                label="Name"
                placeholder="e.g. Payments failure spike"
              />
              <.input
                field={@form[:trigger_type]}
                type="select"
                label="Trigger"
                options={trigger_options()}
              />
              <.input
                field={@form[:threshold]}
                type="text"
                label="Threshold"
                placeholder="anomaly 3.0 · failure-rate 0.05 · DLQ 100"
              />
              <.input
                field={@form[:cooldown_minutes]}
                type="number"
                label="Cooldown (minutes)"
                min="0"
              />
            </div>

            <div class="divider text-sm text-base-content/50">Channels (fill any that apply)</div>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <.input
                field={@form[:email_to]}
                type="text"
                label="Email to"
                placeholder="ops@acme.com"
              />
              <.input
                field={@form[:webhook_url]}
                type="text"
                label="Webhook URL"
                placeholder="https://…"
              />
              <.input
                field={@form[:slack_url]}
                type="text"
                label="Slack webhook URL"
                placeholder="https://hooks.slack.com/…"
              />
            </div>

            <div class="flex items-center gap-2 mt-4">
              <button type="submit" class="btn btn-primary btn-sm">Save rule</button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_form">
                Cancel
              </button>
            </div>
          </.form>
        </div>
      </div>

      <%!-- Rules list --%>
      <div :if={@alerting_entitled} class="card bg-base-100 shadow-sm border border-base-200">
        <div class="card-body p-0">
          <div :if={@rules == []} class="flex flex-col items-center justify-center py-16 text-center">
            <div class="p-4 bg-base-200 rounded-full mb-4">
              <.icon name="hero-bell-slash" class="w-12 h-12 text-base-content/40" />
            </div>
            <h3 class="text-lg font-semibold">No alert rules yet</h3>
            <p class="text-base-content/60 mt-2 max-w-md">
              Create a rule to be notified about anomalies, failures, or a growing dead-letter queue.
            </p>
          </div>

          <table :if={@rules != []} class="table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Trigger</th>
                <th>Channels</th>
                <th>Cooldown</th>
                <th>Last fired</th>
                <th>Enabled</th>
                <th class="text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={rule <- @rules} id={"alert-rule-#{rule.id}"} class="hover">
                <td class="font-medium">{rule.name}</td>
                <td><span class="badge badge-ghost">{trigger_label(rule.trigger_type)}</span></td>
                <td class="text-sm text-base-content/70">{channels_summary(rule.channels)}</td>
                <td class="text-sm">{rule.cooldown_minutes}m</td>
                <td class="text-sm text-base-content/70">{format_timestamp(rule.last_fired_at)}</td>
                <td>
                  <input
                    type="checkbox"
                    class="toggle toggle-sm toggle-success"
                    checked={rule.enabled}
                    phx-click="toggle_rule"
                    phx-value-id={rule.id}
                    phx-value-enabled={to_string(!rule.enabled)}
                  />
                </td>
                <td class="text-right whitespace-nowrap">
                  <button class="btn btn-xs btn-ghost" phx-click="test_rule" phx-value-id={rule.id}>
                    <.icon name="hero-paper-airplane" class="w-4 h-4" /> Test
                  </button>
                  <button class="btn btn-xs btn-ghost" phx-click="edit_rule" phx-value-id={rule.id}>
                    <.icon name="hero-pencil-square" class="w-4 h-4" /> Edit
                  </button>
                  <button
                    class="btn btn-xs btn-ghost text-error"
                    phx-click="delete_rule"
                    phx-value-id={rule.id}
                    data-confirm="Delete this alert rule? This cannot be undone."
                  >
                    <.icon name="hero-trash" class="w-4 h-4" /> Delete
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%!-- History --%>
      <div
        :if={@alerting_entitled && @history != []}
        class="card bg-base-100 shadow-sm border border-base-200"
      >
        <div class="card-body">
          <h2 class="card-title text-base font-bold mb-2">Recent alerts</h2>
          <table class="table table-sm">
            <thead>
              <tr>
                <th>When</th>
                <th>Trigger</th>
                <th>Channels notified</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={entry <- @history} id={"alert-history-#{entry.id}"}>
                <td class="text-sm text-base-content/70">{format_timestamp(entry.inserted_at)}</td>
                <td><span class="badge badge-ghost">{trigger_label(entry.trigger_type)}</span></td>
                <td class="text-sm text-base-content/70">
                  {channels_sent_summary(entry.channels_sent)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # -- View helpers --

  defp trigger_options do
    Enum.map(Alerts.trigger_types(), fn t -> {trigger_label(t), to_string(t)} end)
  end

  defp trigger_label(:anomaly), do: "Anomaly detected"
  defp trigger_label(:failure_rate), do: "Pipeline failure rate"
  defp trigger_label(:pipeline_stopped), do: "Pipeline stopped unexpectedly"
  defp trigger_label(:dlq_depth), do: "DLQ depth"
  defp trigger_label(:freshness_slo), do: "Source freshness SLO missed"
  defp trigger_label(:volume_anomaly), do: "Source volume anomaly"
  defp trigger_label(:schema_drift), do: "Source schema drift"

  defp trigger_label(other) when is_binary(other),
    do: other |> String.to_existing_atom() |> trigger_label()

  defp trigger_label(other), do: other |> to_string() |> String.replace("_", " ")

  defp channels_summary([]), do: "—"

  defp channels_summary(channels) when is_list(channels) do
    channels |> Enum.map(&(&1["type"] || &1[:type])) |> Enum.join(", ")
  end

  defp channels_summary(_), do: "—"

  defp channels_sent_summary(sent) when is_map(sent) and map_size(sent) > 0 do
    sent
    |> Enum.map(fn {ch, status} -> "#{ch}: #{status_label(status)}" end)
    |> Enum.join(", ")
  end

  defp channels_sent_summary(_), do: "—"

  defp status_label("ok"), do: "✓"
  defp status_label(:ok), do: "✓"
  defp status_label(other), do: to_string(other)

  defp format_timestamp(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  defp format_timestamp(_), do: "—"
end
