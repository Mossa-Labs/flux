defmodule Flux.ObservabilityTestProvider do
  @moduledoc """
  In-memory `Flux.Observability.Provider` for tests, standing in for the Postgres +
  ETS detector-backed provider that ships in the commercial edition. Source health
  and SLOs are held in an Agent so reads/writes round-trip without a Pro schema.

  Install with `Flux.Observability.Registry.set_active/1` and reset on exit:

      Flux.ObservabilityTestProvider.reset(health: [...])
      Flux.Observability.Registry.set_active(Flux.ObservabilityTestProvider)
      on_exit(fn -> Flux.Observability.Registry.set_active(Flux.Observability.Providers.Community) end)

  Tests using it MUST be `async: false` (the registry is a global ETS table).
  """

  @behaviour Flux.Observability.Provider

  @agent __MODULE__.Agent

  @doc "Resets to a known set of source-health maps (keyed by org), default empty."
  def reset(opts \\ []) do
    health = Keyword.get(opts, :health, %{})
    slos = Keyword.get(opts, :slos, %{})
    state = %{health: health, slos: slos}

    case Process.whereis(@agent) do
      nil -> Agent.start_link(fn -> state end, name: @agent)
      _ -> Agent.update(@agent, fn _ -> state end)
    end

    :ok
  end

  defp state, do: Agent.get(@agent, & &1)

  @impl true
  def list_source_health(org_id), do: Map.get(state().health, org_id, [])

  @impl true
  def get_slo(org_id, source) do
    case state().slos[{org_id, source}] do
      nil -> {:error, :not_found}
      slo -> {:ok, slo}
    end
  end

  @impl true
  def upsert_slo(org_id, source, attrs) do
    slo = %{
      source: source,
      expected_interval_seconds: attrs["expected_interval_seconds"],
      warn_after_seconds: attrs["warn_after_seconds"],
      enabled: Map.get(attrs, "enabled", true)
    }

    Agent.update(@agent, fn st -> put_in(st.slos[{org_id, source}], slo) end)
    {:ok, slo}
  end

  @impl true
  def delete_slo(org_id, source) do
    Agent.update(@agent, fn st -> %{st | slos: Map.delete(st.slos, {org_id, source})} end)
    :ok
  end

  @impl true
  def list_recent_drift(_org_id, _source), do: []
end
