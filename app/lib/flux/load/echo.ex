defmodule Flux.Load.Echo do
  @moduledoc """
  Tiny local HTTP target for the HTTP-sink benchmark.

  Starts a Bandit server on an ephemeral port whose handler counts every request
  (via `:counters`, lock-free) and returns `200 {}`. Lets the benchmark measure
  sink delivery throughput against a near-zero-overhead endpoint and cross-check
  the delivered count.
  """

  alias Flux.Load.Echo.Handler

  @doc """
  Starts the echo server. Returns `{:ok, info}` where `info` carries the
  listening `:port`, the Bandit supervisor `:pid`, and the `:counter` ref.
  """
  def start_link do
    counter = :counters.new(1, [:write_concurrency])
    port = free_port()

    {:ok, pid} =
      Bandit.start_link(plug: {Handler, counter: counter}, scheme: :http, port: port)

    {:ok, %{pid: pid, port: port, counter: counter}}
  end

  @doc "Total requests received so far."
  def count(%{counter: counter}), do: :counters.get(counter, 1)

  @doc "Stops the echo server."
  def stop(%{pid: pid}) do
    if Process.alive?(pid), do: Supervisor.stop(pid)
    :ok
  end

  # Grab a free port by briefly binding to port 0. There is a small race between
  # closing here and Bandit binding, but it is acceptable for a local, on-demand
  # benchmark target.
  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end
end
