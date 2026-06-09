defmodule Flux.MeteringTestProvider do
  @moduledoc """
  Configurable `Flux.Metering.Provider` for tests, standing in for the Pro
  provider that ships in the commercial edition. Drive its responses via
  `Application` env and install it with `Flux.Metering.Registry.set_active/1`:

      Flux.Metering.Registry.set_active(Flux.MeteringTestProvider)
      Application.put_env(:flux, :test_metering_quota, {:error, {:quota_exceeded, 30}})
      on_exit(fn -> Flux.Metering.Registry.set_active(Flux.Metering.Providers.Community) end)

  Tests using it MUST be `async: false` (the registry is a global ETS table).
  """

  @behaviour Flux.Metering.Provider

  @default_usage %{
    period: %{start: ~D[2026-06-01], end: ~D[2026-06-30]},
    metrics: %{
      messages_ingested: 1_234,
      messages_processed: 1_200,
      sink_deliveries: 800,
      active_pipelines: 3,
      pipeline_hours: 42.5
    },
    quota: %{unlimited: false, limit: 10_000, usage: 1_234, pct: 12.34, state: :ok}
  }

  @impl true
  def get_usage(_organization_id, _opts),
    do: {:ok, Application.get_env(:flux, :test_metering_usage, @default_usage)}

  @impl true
  def check_quota(_organization_id),
    do: Application.get_env(:flux, :test_metering_quota, :ok)

  @impl true
  def quota_status(_organization_id),
    do: Application.get_env(:flux, :test_metering_quota_status, @default_usage.quota)
end
