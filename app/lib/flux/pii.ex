defmodule Flux.PII do
  @moduledoc """
  Facade over the active `Flux.PII.Provider` for redaction metrics (MOS-480).

  The gated `/redaction` dashboard routes all reads through this module rather
  than calling a provider directly. PII redaction/classification is an
  Enterprise feature: the Community build resolves to
  `Flux.PII.Providers.Community` (a no-op stub); the Enterprise edition overlays
  the telemetry-backed `Flux.PII.Aggregator` via `Flux.PII.Registry.set_active/1`
  once `:pii_redaction` is entitled.

  ## Telemetry contract

  The Enterprise `redact` step emits, once per scanned message:

      :telemetry.execute(
        [:flux, :pii, :redaction],
        %{messages_scanned: 1, messages_redacted: 0 | 1, pii_instances: n},
        %{
          organization_id: term(),
          pipeline_id: term(),
          by_type: %{"email" => n, "ssn" => n, ...},   # counts only
          by_field: %{"user.email" => %{"email" => n}, ...}
        }
      )

  Measurements and metadata carry **only counts and field paths — never PII
  values**. The Enterprise aggregator attaches a handler to this event; the
  Community build has no handler (nothing consumes it), which is why the read
  side returns the empty shape.

  See `Flux.PII.Provider` for the stats map shape.
  """

  alias Flux.PII.Provider
  alias Flux.PII.Registry

  @telemetry_event [:flux, :pii, :redaction]

  @doc "The telemetry event name the `redact` step emits and the aggregator handles."
  @spec telemetry_event() :: [atom()]
  def telemetry_event, do: @telemetry_event

  @doc """
  Redaction metrics for `organization_id`, optionally scoped to `pipeline_id`.

  See `Flux.PII.Provider.stats/3` for `opts` and the returned shape.
  """
  @spec stats(Provider.organization_id(), Provider.pipeline_id(), keyword()) :: Provider.stats()
  def stats(organization_id, pipeline_id \\ nil, opts \\ []) do
    Registry.active().stats(organization_id, pipeline_id, opts)
  end
end
