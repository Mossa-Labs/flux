defmodule Flux.Load.Generator do
  @moduledoc """
  Synthetic message generator for the load harness.

  Injects messages through `Flux.Pipeline.Producers.Memory.push_message/2`, which
  is an async PubSub broadcast with no producer-side backpressure — so the
  generator paces itself.

  Two modes:

    * **Rate-limited** (`rate > 0`): token-bucket pacing in ~10ms ticks, sending
      `rate * 10/1000` messages per tick and sleeping to the next tick boundary
      (drift-corrected against a monotonic clock).
    * **Max throughput** (`rate == 0`): a tight push loop, letting Broadway's
      processor concurrency be the ceiling.

  Stops at `:count` messages or when `:duration_ms` elapses, whichever comes
  first. Messages are shaped by `:gen_fun` (`index -> map`) and fanned across
  `:queues` round-robin.
  """

  alias Flux.Pipeline.Producers.Memory, as: MemoryProducer

  @tick_ms 10

  @doc """
  Runs the generator. Returns `{messages_sent, elapsed_ms}`.

  ## Options

    * `:queues` (required) — list of source-queue names to fan messages across.
    * `:gen_fun` (required) — `index -> map`, builds each message payload.
    * `:rate` — target messages/sec; `0` (default) means max throughput.
    * `:count` — stop after this many messages (default: unbounded).
    * `:duration_ms` — stop after this many ms (default: unbounded).
  """
  def run(opts) do
    queues = opts |> Keyword.fetch!(:queues) |> List.to_tuple()
    gen_fun = Keyword.fetch!(opts, :gen_fun)
    rate = Keyword.get(opts, :rate, 0)
    count = Keyword.get(opts, :count)
    duration_ms = Keyword.get(opts, :duration_ms)

    start = now()
    deadline = duration_ms && start + duration_ms

    sent =
      if rate > 0 do
        per_tick = max(1, div(rate * @tick_ms, 1000))
        paced(queues, gen_fun, per_tick, count, deadline, start, 0, 1)
      else
        maxed(queues, gen_fun, count, deadline, 0)
      end

    {sent, now() - start}
  end

  # -- Rate-limited pacing --

  defp paced(queues, gen_fun, per_tick, count, deadline, start, sent, tick) do
    cond do
      done?(count, sent, deadline) ->
        sent

      true ->
        to_send = if count, do: min(per_tick, count - sent), else: per_tick
        sent = push_n(queues, gen_fun, sent, to_send)

        target = start + tick * @tick_ms
        sleep_until(target)

        paced(queues, gen_fun, per_tick, count, deadline, start, sent, tick + 1)
    end
  end

  # -- Max throughput --

  defp maxed(queues, gen_fun, count, deadline, sent) do
    if done?(count, sent, deadline) do
      sent
    else
      maxed(queues, gen_fun, count, deadline, push_n(queues, gen_fun, sent, 1))
    end
  end

  # -- Shared helpers --

  defp push_n(_queues, _gen_fun, sent, 0), do: sent

  defp push_n(queues, gen_fun, sent, n) do
    idx = sent + 1
    queue = elem(queues, rem(sent, tuple_size(queues)))
    MemoryProducer.push_message(queue, gen_fun.(idx))
    push_n(queues, gen_fun, idx, n - 1)
  end

  defp done?(count, sent, deadline) do
    (count && sent >= count) || (deadline && now() >= deadline) || false
  end

  defp sleep_until(target) do
    remaining = target - now()
    if remaining > 0, do: Process.sleep(remaining)
  end

  defp now, do: System.monotonic_time(:millisecond)
end
