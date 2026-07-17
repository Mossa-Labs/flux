defmodule Flux.Audit.Providers.Community do
  @moduledoc """
  Community no-op audit provider.

  Audit logging is an **Enterprise** feature. `log/1` accepts and discards events
  (keeping mutating-context call sites total and zero-cost with no `audit_logs`
  table present); reads return empty; `export/2` returns
  `{:error, {:pro_required, :audit_log}}`. The gated `/system/audit-logs`
  LiveView and `/api/audit-logs` endpoint short-circuit to an upgrade prompt /
  403 (via `Flux.License.has_feature?(:audit_log)`) before reaching these, but
  the stub keeps the facade crash-free everywhere.
  """

  @behaviour Flux.Audit.Provider

  @pro_required {:error, {:pro_required, :audit_log}}

  @impl true
  def log(_event), do: :ok

  @impl true
  def list(_organization_id, _filters, _opts), do: []

  @impl true
  def count(_organization_id, _filters), do: 0

  @impl true
  def export(_organization_id, _filters), do: @pro_required

  @impl true
  def prune(_opts), do: :ok
end
