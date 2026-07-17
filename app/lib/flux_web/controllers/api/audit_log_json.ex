defmodule FluxWeb.API.AuditLogJSON do
  @moduledoc "JSON rendering for the audit-log API (MOS-482)."

  def index(%{entries: entries, total: total, limit: limit, offset: offset}) do
    %{
      data: Enum.map(entries, &entry/1),
      meta: %{total: total, limit: limit, offset: offset}
    }
  end

  defp entry(e) do
    %{
      id: e[:id],
      actor_id: e[:actor_id],
      actor_type: e[:actor_type],
      action: e[:action],
      resource_type: e[:resource_type],
      resource_id: e[:resource_id],
      changes: e[:changes] || %{},
      metadata: e[:metadata] || %{},
      inserted_at: e[:inserted_at]
    }
  end
end
