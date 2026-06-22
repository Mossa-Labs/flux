defmodule Flux.Load.Echo.Handler do
  @moduledoc """
  Minimal Plug for `Flux.Load.Echo`: increments a shared `:counters` ref on every
  request and replies `200 {}`. Used as a near-zero-overhead delivery target for
  the HTTP-sink benchmark.
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    :counters.add(Keyword.fetch!(opts, :counter), 1, 1)
    send_resp(conn, 200, "{}")
  end
end
