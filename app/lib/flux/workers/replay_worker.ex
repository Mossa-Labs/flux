defmodule Flux.Workers.ReplayWorker do
  @moduledoc """
  Oban worker that bulk-replays dead-lettered messages matching a set of filters
  (MOS-474). Enqueued by `Flux.Queue.Replay.replay_messages/2`.

  It loops `Flux.Queue.replay_dlq/2` in batches until the adapter reports the
  filtered set is exhausted, broadcasting `{:replay_progress, progress}` on the
  `Flux.Queue.Replay.topic/1` channel after each batch and `{:replay_done,
  progress}` on completion. The final tally is recorded to alert history via
  `Flux.Alerts.record_event/2` (a no-op in Community).

  Replay only works when the active queue adapter implements DLQ replay (EE
  brokers). Under Community/Memory the first `replay_dlq/2` returns
  `{:error, {:pro_required, :dlq}}`; the worker records the failure and stops.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Flux.Queue
  alias Flux.Queue.Replay

  require Logger

  @default_batch_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: args}) do
    org_id = args["organization_id"]
    filters = build_filters(args["filters"])
    batch_size = args["batch_size"] || @default_batch_size

    initial = %{Replay.zero_progress() | total: starting_total()}
    final = drain(filters, batch_size, initial, job_id)

    broadcast(job_id, {:replay_done, final})
    record_event(org_id, final, args["filters"])

    :ok
  end

  defp drain(filters, batch_size, progress, job_id) do
    case Queue.replay_dlq(filters, batch_size) do
      {:ok, %{replayed: replayed, skipped: skipped, exhausted?: exhausted?}} ->
        progress = %{
          progress
          | processed: progress.processed + replayed,
            skipped: progress.skipped + skipped
        }

        progress = if exhausted?, do: reconcile_total(progress), else: progress
        broadcast(job_id, {:replay_progress, progress})

        if exhausted? do
          progress
        else
          drain(filters, batch_size, progress, job_id)
        end

      {:error, reason} ->
        Logger.error("DLQ replay batch failed", reason: inspect(reason))
        reconcile_total(%{progress | failed: progress.failed + 1})
    end
  end

  defp starting_total do
    case Queue.dlq_depth() do
      {:ok, depth} -> depth
      _ -> 0
    end
  end

  defp reconcile_total(progress) do
    seen = progress.processed + progress.skipped + progress.failed
    %{progress | total: max(progress.total, seen)}
  end

  defp broadcast(job_id, message) do
    Phoenix.PubSub.broadcast(Flux.PubSub, Replay.topic(job_id), message)
  end

  defp record_event(nil, _progress, _filters), do: :ok

  defp record_event(org_id, progress, filters) do
    Flux.Alerts.record_event(org_id, %{
      trigger_type: :dlq_replay,
      trigger_data: %{
        "total" => progress.total,
        "processed" => progress.processed,
        "skipped" => progress.skipped,
        "failed" => progress.failed,
        "filters" => filters || %{}
      },
      channels_sent: %{}
    })
  end

  # -- Filter decoding (string-keyed Oban args -> adapter replay_filters) --

  defp build_filters(nil), do: %{}

  defp build_filters(filters) when is_map(filters) do
    %{}
    |> put_present(:queue, filters["queue"])
    |> put_present(:source, filters["source"])
    |> put_present(:time_range, decode_time_range(filters["time_range"]))
  end

  defp decode_time_range(%{"from" => from, "to" => to}) do
    with {:ok, from_dt, _} <- DateTime.from_iso8601(from),
         {:ok, to_dt, _} <- DateTime.from_iso8601(to) do
      %{from: from_dt, to: to_dt}
    else
      _ -> nil
    end
  end

  defp decode_time_range(_), do: nil

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)
end
