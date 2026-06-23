defmodule FluxWeb.ObservabilityLive.Index do
  @moduledoc """
  Pro-gated observability fleet view (MOS-472).

  Lists every source the org has ingested with freshness-SLO, volume-baseline, and
  schema-drift health, and lets operators configure per-source freshness SLOs. Real
  data is served by the active `Flux.Observability.Provider` (the Pro Postgres + ETS
  detector); Community builds surface an upgrade prompt.

  Anomalies route to notification channels through the alerting feature's
  `freshness_slo`/`volume_anomaly`/`schema_drift` trigger types (see `/system/alerts`).
  """
  use FluxWeb, :live_view

  alias Flux.Observability
  alias FluxWeb.Components.ObservabilityCards
  alias FluxWeb.Components.UpgradePrompt

  @refresh_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    entitled? = Flux.License.has_feature?(:observability)

    if connected?(socket) and entitled?, do: Process.send_after(self(), :refresh, @refresh_ms)

    {:ok,
     socket
     |> assign(:active_tab, :observability)
     |> assign(:page_title, "Observability")
     |> assign(:observability_entitled, entitled?)
     |> assign(:sources, [])
     |> load_sources()}
  end

  defp load_sources(%{assigns: %{observability_entitled: true}} = socket) do
    org_id = socket.assigns.current_scope.organization_id
    assign(socket, :sources, Observability.list_source_health(org_id))
  end

  defp load_sources(socket), do: socket

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, load_sources(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("save_slo", %{"slo" => %{"source" => source} = params}, socket) do
    org_id = socket.assigns.current_scope.organization_id

    attrs = %{
      "expected_interval_seconds" => parse_int(params["expected_interval_seconds"]),
      "warn_after_seconds" => parse_int(params["warn_after_seconds"]),
      "enabled" => true
    }

    case Observability.upsert_slo(org_id, source, attrs) do
      {:ok, _slo} ->
        {:noreply,
         socket |> put_flash(:info, "Freshness SLO saved for #{source}.") |> load_sources()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not save SLO: #{format_error(reason)}")}
    end
  end

  defp parse_int(nil), do: nil

  defp parse_int(value) do
    case Integer.parse(to_string(value)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp format_error({:pro_required, _}), do: "requires Flux Pro"
  defp format_error(reason), do: inspect(reason)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-2xl font-bold tracking-tight text-base-content">Observability</h1>
        <p class="text-base-content/60 mt-1">
          Freshness SLOs, volume baselines, and schema drift across your sources
        </p>
      </div>

      <UpgradePrompt.upgrade_prompt :if={!@observability_entitled} feature={:observability} />

      <div
        :if={@observability_entitled && @sources == []}
        class="card bg-base-100 shadow-sm border border-base-200"
      >
        <div class="card-body flex flex-col items-center justify-center py-16 text-center">
          <div class="p-4 bg-base-200 rounded-full mb-4">
            <.icon name="hero-signal" class="w-12 h-12 text-base-content/40" />
          </div>
          <h3 class="text-lg font-semibold">No sources observed yet</h3>
          <p class="text-base-content/60 mt-2 max-w-md">
            Once webhooks arrive, each source shows up here with freshness, volume, and schema health.
          </p>
        </div>
      </div>

      <div :if={@observability_entitled} class="space-y-4">
        <ObservabilityCards.source_card
          :for={health <- @sources}
          health={health}
          editable={true}
        />
      </div>
    </div>
    """
  end
end
