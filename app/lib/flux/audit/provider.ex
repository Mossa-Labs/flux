defmodule Flux.Audit.Provider do
  @moduledoc """
  Contract for audit-log providers (MOS-482).

  Community ships `Flux.Audit.Providers.Community` — a no-op stub: `log/1`
  returns `:ok` (writing nothing), reads return empty, and `export/2` returns
  `{:error, {:pro_required, :audit_log}}`. Audit logging is an **Enterprise**
  feature (Pro does not get it); the commercial edition ships a provider backed
  by Postgres (`audit_logs`) with SQL-side filtering/pagination, streamed export,
  and retention pruning.

  Callers use the `Flux.Audit` facade, which resolves the active provider via
  `Flux.Audit.Registry`. Keeping the schema out of this repo means the public
  side carries only the gating scaffolding — no proprietary implementation.

  ## Event map

  `log/1` receives a normalized event (built by `Flux.Audit.Event`):

      %{
        organization_id: integer() | binary() | nil,
        actor_id: integer() | binary() | nil,
        actor_type: :user | :system | :api_key,
        action: String.t(),            # e.g. "pipeline_updated"
        resource_type: String.t() | nil,
        resource_id: String.t() | nil,
        changes: map(),                # JSONB diff (may be empty)
        metadata: map()                # JSONB: ip_address, user_agent, api_key_prefix
      }

  Read functions return entries as plain maps (the public side has no Ecto
  schema), mirroring `Flux.Alerts.Provider`:

      %{
        id: term(),
        organization_id: term(),
        actor_id: term() | nil,
        actor_type: String.t(),
        action: String.t(),
        resource_type: String.t() | nil,
        resource_id: String.t() | nil,
        changes: map(),
        metadata: map(),
        inserted_at: DateTime.t()
      }

  ## Filters

  `filters` is a map that may include `:actor_id`, `:action`, `:resource_type`,
  `:resource_id`, `:from` (`DateTime`), and `:to` (`DateTime`). Blank/nil keys
  are ignored by the provider.
  """

  @type organization_id :: integer() | binary()
  @type filters :: map()
  @type entry :: map()

  @doc "Records one audit event. Fire-and-forget; must never raise."
  @callback log(event :: map()) :: :ok

  @doc "Lists entries for an org, newest first, filtered + paginated (limit/offset)."
  @callback list(organization_id(), filters(), opts :: keyword()) :: [entry()]

  @doc "Total entries matching `filters` (for pagination)."
  @callback count(organization_id(), filters()) :: non_neg_integer()

  @doc "Streams matching entries for export, or `{:error, term}` when unavailable."
  @callback export(organization_id(), filters()) :: Enumerable.t() | {:error, term()}

  @doc "Prunes entries older than the retention window. Returns count deleted."
  @callback prune(opts :: keyword()) :: {:ok, non_neg_integer()} | :ok
end
