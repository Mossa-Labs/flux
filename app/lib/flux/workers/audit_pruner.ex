defmodule Flux.Workers.AuditPruner do
  @moduledoc """
  Nightly Oban job that prunes audit entries past the retention window (MOS-482).

  Delegates to `Flux.Audit.prune/1`, which routes to the active provider: a
  no-op on Community (no audit store) and the actual retention delete on the
  Enterprise provider. Scheduled via `Oban.Plugins.Cron` in `config/config.exs`.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    retention_days = Application.get_env(:flux, Flux.Audit)[:retention_days] || 90

    case Flux.Audit.prune(retention_days: retention_days) do
      {:ok, count} ->
        Logger.info("[Flux.Workers.AuditPruner] pruned #{count} audit entries")
        :ok

      :ok ->
        :ok
    end
  end
end
