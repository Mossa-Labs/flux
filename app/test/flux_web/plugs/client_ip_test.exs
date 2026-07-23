defmodule FluxWeb.Plugs.ClientIpTest do
  # async: false — reads/writes the app env for trusted proxies.
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  defp resolve(peer_ip, xff) do
    conn(:get, "/")
    |> Map.put(:remote_ip, peer_ip)
    |> put_req_header("x-forwarded-for", xff)
    |> FluxWeb.Plugs.ClientIp.call([])
  end

  test "ignores X-Forwarded-For when no trusted proxies are configured (default)" do
    conn = resolve({203, 0, 113, 1}, "1.2.3.4")
    # Spoofed XFF from an untrusted peer must not change the client IP.
    assert conn.remote_ip == {203, 0, 113, 1}
  end

  test "honors X-Forwarded-For only from a trusted proxy peer" do
    Application.put_env(:flux, FluxWeb.Plugs.ClientIp, proxies: ["203.0.113.0/24"])
    on_exit(fn -> Application.put_env(:flux, FluxWeb.Plugs.ClientIp, proxies: []) end)

    conn = resolve({203, 0, 113, 1}, "198.51.100.23")
    assert conn.remote_ip == {198, 51, 100, 23}
  end
end
