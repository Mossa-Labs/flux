defmodule Flux.Queue.Replay do
  @moduledoc """
  Filtered, progress-tracked bulk replay of dead-lettered messages (MOS-474).

  This is the orchestration/facade layer. The actual filtered drain runs in the
  active queue adapter's `replay_dlq/2` callback (a Pro feature; only EE broker
  adapters implement it). `replay_messages/2` normalizes UI filters and enqueues
  a `Flux.Workers.ReplayWorker` Oban job, which loops `Flux.Queue.replay_dlq/2`
  in batches and broadcasts progress on the `topic/1` PubSub channel.

  Single-message and selected-message replay still go through the synchronous
  `Flux.Queue.retry_message/1` (delivery tags are session-bound and cannot cross
  into a background worker); this module is only for whole-DLQ filtered replays.

  ## Filters

  A plain map; all keys optional and ANDed. Accepts atom or string keys:

    * `time_range` - `%{from: DateTime | iso8601, to: DateTime | iso8601}`
    * `queue` - exact original-queue match
    * `source` - exact source match
    * `pipeline_id` - resolved here to the pipeline's `source_queue`

  ## Progress

  `%{total: n, processed: n, failed: n, skipped: n}` - `total` is seeded from the
  DLQ depth at start (a best-effort upper bound) and reconciled on completion.
  """

  alias Flux.Workers.ReplayWorker

  @type progress :: %{
          total: non_neg_integer(),
          processed: non_neg_integer(),
          failed: non_neg_integer(),
          skipped: non_neg_integer()
        }

  @default_batch_size 100

  @doc """
  PubSub topic carrying `{:replay_progress, progress}` and `{:replay_done,
  progress}` messages for an enqueued replay job.
  """
  @spec topic(term()) :: String.t()
  def topic(job_id), do: "replay:#{job_id}"

  @doc "Zero-valued progress map."
  @spec zero_progress() :: progress()
  def zero_progress, do: %{total: 0, processed: 0, failed: 0, skipped: 0}

  @doc """
  Normalizes `filters` and enqueues a `Flux.Workers.ReplayWorker` job that bulk
  replays matching dead-lettered messages back to their original queues.

  ## Options

    * `:organization_id` (required) - scopes `pipeline_id` resolution and the
      alert-history event recorded on completion.
    * `:batch_size` - messages drained per `replay_dlq/2` call
      (default `#{@default_batch_size}`).

  Returns `{:ok, %Oban.Job{}}`, or `{:error, :pipeline_not_found}` when a
  `pipeline_id` filter does not resolve within the organization.
  """
  @spec replay_messages(map(), keyword()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def replay_messages(filters, opts) do
    org_id = Keyword.fetch!(opts, :organization_id)

    with {:ok, normalized} <- normalize_filters(filters, org_id) do
      %{
        "organization_id" => org_id,
        "filters" => normalized,
        "batch_size" => Keyword.get(opts, :batch_size, @default_batch_size)
      }
      |> ReplayWorker.new()
      |> Oban.insert()
    end
  end

  @doc """
  Normalizes a raw UI filter map into the JSON-safe, string-keyed form stored in
  the worker's Oban args. Resolves `pipeline_id` to its `source_queue`.

  Exposed for testing; `replay_messages/2` calls it internally.
  """
  @spec normalize_filters(map(), term()) :: {:ok, map()} | {:error, term()}
  def normalize_filters(filters, org_id) do
    filters = stringify_keys(filters)

    with {:ok, queue} <- resolve_queue(filters, org_id) do
      normalized =
        %{}
        |> put_present("queue", queue)
        |> put_present("source", blank_to_nil(filters["source"]))
        |> put_present("time_range", normalize_time_range(filters["time_range"]))

      {:ok, normalized}
    end
  end

  # -- Filter normalization helpers --

  defp resolve_queue(filters, org_id) do
    case blank_to_nil(filters["pipeline_id"]) do
      nil ->
        {:ok, blank_to_nil(filters["queue"])}

      pipeline_id ->
        case Flux.Pipelines.get_pipeline(to_integer(pipeline_id), org_id) do
          nil -> {:error, :pipeline_not_found}
          pipeline -> {:ok, pipeline.source_queue}
        end
    end
  end

  defp normalize_time_range(nil), do: nil

  defp normalize_time_range(range) do
    range = stringify_keys(range)

    with {:ok, from} <- to_iso8601(range["from"]),
         {:ok, to} <- to_iso8601(range["to"]) do
      %{"from" => from, "to" => to}
    else
      _ -> nil
    end
  end

  defp to_iso8601(%DateTime{} = dt), do: {:ok, DateTime.to_iso8601(dt)}

  defp to_iso8601(value) when is_binary(value) do
    case blank_to_nil(value) do
      nil -> :error
      str -> {:ok, str}
    end
  end

  defp to_iso8601(_), do: :error

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp stringify_keys(_), do: %{}

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)

  defp blank_to_nil(value), do: value

  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_binary(value), do: String.to_integer(value)
end
