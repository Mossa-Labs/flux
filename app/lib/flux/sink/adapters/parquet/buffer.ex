defmodule Flux.Sink.Adapters.Parquet.Buffer do
  @moduledoc """
  Per-`{sink, pipeline}` row buffer for the Parquet sink.

  Rows arrive one at a time from `Flux.Sink.Adapters.Parquet.deliver/3` and are
  held column-wise, grouped by rendered partition. A partition is flushed to its
  own Parquet file when it reaches `max_rows`, when it has been open for
  `max_interval_seconds`, when an incoming record forces a schema rotation, or
  when the buffer shuts down (it traps exits so `terminate/2` always runs on a
  supervised stop).

  The buffer keeps a *seed schema* — the latest schema it has written with — so
  a new file starts from the shape the previous one ended with rather than
  re-inferring from a single record (which would rotate again on the next
  wider record).

  After `idle_timeout_ms` with nothing buffered the process exits `:normal`, so
  buffers for deleted sinks or stopped pipelines do not linger.

  Buffered rows live in memory: a hard VM kill loses whatever has not been
  flushed yet. That matches the delivery semantics of every other sink, whose
  result does not affect the message ack.
  """

  use GenServer, restart: :transient

  require Logger

  alias Flux.Sink.Adapters.Parquet.{Paths, Schema, Settings, Writer}

  @registry Flux.Sink.Adapters.Parquet.BufferRegistry
  @default_idle_timeout_ms 300_000
  @default_max_open_partitions 500
  @write_attempts 3

  defstruct [
    :key,
    :pipeline_id,
    :config_hash,
    :settings,
    :schema,
    :last_activity,
    partitions: %{},
    seq: 0
  ]

  # ── Client ──────────────────────────────────────────────────────────────

  # terminate/2 writes every open partition, which can legitimately take a
  # while (up to max_open_partitions files on slow storage). A fixed stop limit
  # would let the supervisor kill the buffer mid-flush and drop rows it already
  # accepted, so by default shutdown waits for the flush to finish. Operators
  # can bound it with `config :flux, Flux.Sink.Adapters.Parquet, shutdown_timeout:`.
  def child_spec(opts) do
    opts
    |> super()
    |> Map.put(:shutdown, env(:shutdown_timeout, :infinity))
  end

  def start_link(opts) do
    key = Keyword.fetch!(opts, :key)
    GenServer.start_link(__MODULE__, opts, name: via(key))
  end

  @doc "The registered name for the buffer owning `key`."
  def via(key), do: {:via, Registry, {@registry, key}}

  @doc "Appends one row; returns once it is buffered (or rejected)."
  @spec append(GenServer.server(), map(), map(), timeout()) :: :ok | {:error, term()}
  def append(server, row, config, timeout \\ 30_000) do
    GenServer.call(server, {:append, row, config}, timeout)
  end

  @doc "Flushes every open partition now."
  @spec flush(GenServer.server()) :: :ok
  def flush(server), do: GenServer.call(server, :flush, 60_000)

  # ── Server ──────────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    {_sink, pipeline_id} = key = Keyword.fetch!(opts, :key)
    config = Keyword.fetch!(opts, :config)

    state = %__MODULE__{
      key: key,
      pipeline_id: pipeline_id,
      config_hash: :erlang.phash2(config),
      settings: Settings.from_config(config),
      last_activity: now_ms()
    }

    schedule_tick(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:append, row, config}, _from, state) do
    state = state |> reconfigure(config) |> Map.put(:last_activity, now_ms())
    partition = render_partition(state, row)

    case place(state, partition, row) do
      {:ok, state} ->
        {:reply, :ok, enforce_partition_cap(state)}

      {:error, reasons, state} ->
        {:reply, {:error, {:schema_mismatch, reasons}}, state}
    end
  end

  def handle_call(:flush, _from, state), do: {:reply, :ok, flush_all(state)}

  @impl true
  def handle_info(:tick, state) do
    now = now_ms()
    interval = state.settings.interval_ms

    state =
      state.partitions
      |> Enum.filter(fn {_partition, part} -> now - part.opened_at >= interval end)
      |> Enum.reduce(state, fn {partition, _}, state -> flush_partition(state, partition) end)

    if state.partitions == %{} and now - state.last_activity >= idle_timeout_ms() do
      {:stop, :normal, state}
    else
      schedule_tick(state)
      {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    _ = flush_all(state)
    :ok
  end

  # ── Placement ───────────────────────────────────────────────────────────

  # Explicit schema: fixed columns, lenient coercion, no rotation.
  defp place(%{settings: %{schema: schema}} = state, partition, row) when is_map(schema) do
    case Schema.fit_explicit(schema, row) do
      {:ok, coerced} -> {:ok, add_row(state, partition, schema, coerced)}
      {:error, reasons} -> {:error, reasons, state}
    end
  end

  defp place(state, partition, row) do
    case Map.fetch(state.partitions, partition) do
      {:ok, part} -> place_existing(state, partition, part.schema, row)
      :error -> place_new(state, partition, row)
    end
  end

  # A fresh file starts from the seed schema; nothing is buffered for this
  # partition, so a mismatch just widens the starting schema (strict rejects).
  defp place_new(state, partition, row) do
    base = state.schema || Schema.infer(row)

    case Schema.fit(base, row) do
      {:ok, schema, coerced} ->
        {:ok, add_row(state, partition, schema, coerced)}

      {:mismatch, reasons} when state.settings.strict? ->
        {:error, reasons, state}

      {:mismatch, _reasons} ->
        {:ok, schema, coerced} = Schema.fit(Schema.widen(base, row), row)
        {:ok, add_row(state, partition, schema, coerced)}
    end
  end

  defp place_existing(state, partition, schema, row) do
    case Schema.fit(schema, row) do
      {:ok, schema, coerced} ->
        {:ok, add_row(state, partition, schema, coerced)}

      {:mismatch, reasons} when state.settings.strict? ->
        {:error, reasons, state}

      {:mismatch, reasons} ->
        Logger.info("Parquet sink rotating file on schema change: #{Enum.join(reasons, "; ")}")
        widened = Schema.widen(schema, row)
        state = flush_partition(%{state | schema: widened}, partition)
        {:ok, schema, coerced} = Schema.fit(widened, row)
        {:ok, add_row(state, partition, schema, coerced)}
    end
  end

  defp add_row(state, partition, schema, row) do
    part =
      Map.get_lazy(state.partitions, partition, fn ->
        %{columns: Map.new(Schema.columns(schema), &{&1, []}), rows: 0, opened_at: now_ms()}
      end)

    columns =
      Map.new(schema, fn {name, _} -> {name, [Map.get(row, name) | part.columns[name]]} end)

    part = %{part | columns: columns, rows: part.rows + 1} |> Map.put(:schema, schema)
    # Merge rather than replace: a row landing in an older, narrower partition
    # must not drop columns another partition has already widened the seed with.
    seed = Schema.merge(state.schema || %{}, schema)
    state = %{state | schema: seed, partitions: Map.put(state.partitions, partition, part)}

    if part.rows >= state.settings.max_rows,
      do: flush_partition(state, partition),
      else: state
  end

  # Too many concurrently open partitions (e.g. partitioning on a
  # high-cardinality field) would grow memory without bound — flush the oldest.
  defp enforce_partition_cap(state) do
    if map_size(state.partitions) > max_open_partitions() do
      {oldest, _} = Enum.min_by(state.partitions, fn {_, part} -> part.opened_at end)
      flush_partition(state, oldest)
    else
      state
    end
  end

  # ── Flushing ────────────────────────────────────────────────────────────

  defp flush_all(state) do
    state.partitions
    |> Map.keys()
    |> Enum.reduce(state, &flush_partition(&2, &1))
  end

  defp flush_partition(state, partition) do
    case Map.pop(state.partitions, partition) do
      {nil, _} ->
        state

      # Only empty records were seen: there are no columns to write.
      {%{schema: schema}, partitions} when map_size(schema) == 0 ->
        %{state | partitions: partitions}

      {part, partitions} ->
        seq = state.seq + 1
        write_part(state, partition, part, seq)
        %{state | partitions: partitions, seq: seq}
    end
  end

  defp write_part(state, partition, part, seq) do
    started = System.monotonic_time()
    columns = Map.new(part.columns, fn {name, values} -> {name, Enum.reverse(values)} end)

    result = write_new_file(state, partition, part.schema, columns, seq, @write_attempts)
    emit_flush(state, partition, part.rows, started, result)
  end

  # Renders a fresh name (new {uid} and {timestamp}) for each attempt, so a
  # name collision costs a retry instead of the rows.
  defp write_new_file(state, partition, schema, columns, seq, attempts) do
    settings = state.settings

    relative =
      Paths.render_file(settings.path_template, %{
        pipeline_id: state.pipeline_id,
        partition: partition,
        now: DateTime.utc_now(),
        seq: seq,
        uid: Paths.uid()
      })

    with {:ok, root} <- Paths.root(%{"directory" => settings.directory}),
         {:ok, path} <- Paths.resolve(root, relative),
         {:ok, bytes} <- Writer.write(path, schema, columns, settings.compression) do
      {:ok, path, bytes}
    else
      {:error, :eexist} when attempts > 1 ->
        write_new_file(state, partition, schema, columns, seq, attempts - 1)

      error ->
        error
    end
  end

  defp emit_flush(state, partition, rows, started, result) do
    duration = System.monotonic_time() - started
    {sink, pipeline_id} = state.key

    {status, bytes} =
      case result do
        {:ok, path, bytes} ->
          Logger.debug("Parquet sink wrote #{rows} rows (#{bytes} bytes) to #{path}")
          {:ok, bytes}

        {:error, reason} ->
          Logger.error(
            "Parquet sink #{inspect(sink)} failed to write #{rows} buffered rows " <>
              "for pipeline #{inspect(pipeline_id)}: #{inspect(reason)}"
          )

          {:error, 0}
      end

    :telemetry.execute(
      [:flux, :sink, :parquet, :flush],
      %{rows: rows, bytes: bytes, duration: duration},
      %{sink: sink, pipeline_id: pipeline_id, partition: partition, status: status}
    )
  end

  # ── Helpers ─────────────────────────────────────────────────────────────

  # The runner reloads a sink's config from the DB for every message, so an
  # edit shows up here as a different config. Flush what was buffered under the
  # old settings before adopting the new ones.
  defp reconfigure(state, config) do
    hash = :erlang.phash2(config)

    if hash == state.config_hash do
      state
    else
      state = flush_all(state)
      %{state | config_hash: hash, settings: Settings.from_config(config), schema: nil}
    end
  end

  defp render_partition(state, row) do
    Paths.render_partition(
      state.settings.partition_template,
      row,
      DateTime.utc_now(),
      state.pipeline_id
    )
  end

  # Tick often enough that a partition is flushed within ~25% of its interval
  # (bounded to 100ms..5s), rather than up to a whole extra interval late.
  defp schedule_tick(state) do
    tick = state.settings.interval_ms |> div(4) |> max(100) |> min(5_000)
    Process.send_after(self(), :tick, tick)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp idle_timeout_ms, do: env(:idle_timeout_ms, @default_idle_timeout_ms)
  defp max_open_partitions, do: env(:max_open_partitions, @default_max_open_partitions)

  defp env(key, default) do
    :flux
    |> Application.get_env(Flux.Sink.Adapters.Parquet, [])
    |> Keyword.get(key, default)
  end
end
