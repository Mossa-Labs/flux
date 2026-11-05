defmodule FluxWeb.Plugs.ClientIpTest do
  # async: false — reads/writes the app env for trusted proxies.
  use ExUnit.Case, async: false

  import Plug.Test

  alias FluxWeb.Plugs.ClientIp

  defp resolve(peer_ip, xff_headers) do
    conn = Map.put(conn(:get, "/"), :remote_ip, peer_ip)

    xff_headers
    |> List.wrap()
    |> Enum.reduce(conn, fn value, conn ->
      %{conn | req_headers: conn.req_headers ++ [{"x-forwarded-for", value}]}
    end)
    |> ClientIp.call([])
  end

  defp trust(proxies) do
    Application.put_env(:flux, ClientIp, proxies: proxies)
    on_exit(fn -> Application.put_env(:flux, ClientIp, proxies: []) end)
  end

  describe "with no trusted proxies configured (default)" do
    test "ignores X-Forwarded-For" do
      conn = resolve({203, 0, 113, 1}, "1.2.3.4")
      assert conn.remote_ip == {203, 0, 113, 1}
    end

    test "rewrites an IPv4-mapped IPv6 peer to IPv4" do
      # ::ffff:203.0.113.1 — otherwise an IPv4 allowlist range never matches.
      conn = resolve({0, 0, 0, 0, 0, 0xFFFF, 0xCB00, 0x7101}, [])
      assert conn.remote_ip == {203, 0, 113, 1}
    end
  end

  describe "when the peer is not a trusted proxy" do
    setup do: trust(["10.0.4.0/24"])

    test "an injected X-Forwarded-For cannot set the client IP" do
      conn = resolve({198, 51, 100, 7}, "1.2.3.4")
      assert conn.remote_ip == {198, 51, 100, 7}
    end

    test "even when the injected chain ends in a trusted proxy address" do
      conn = resolve({198, 51, 100, 7}, "1.2.3.4, 10.0.4.2")
      assert conn.remote_ip == {198, 51, 100, 7}
    end

    test "a private peer is not implicitly trusted" do
      conn = resolve({192, 168, 1, 50}, "1.2.3.4")
      assert conn.remote_ip == {192, 168, 1, 50}
    end
  end

  describe "when the peer is a trusted proxy" do
    setup do: trust(["10.0.4.0/24", "2001:db8::/32"])

    test "uses the address the proxy appended" do
      conn = resolve({10, 0, 4, 2}, "198.51.100.23")
      assert conn.remote_ip == {198, 51, 100, 23}
    end

    test "a client-supplied entry left of the real one is ignored" do
      conn = resolve({10, 0, 4, 2}, "9.9.9.9, 198.51.100.23")
      assert conn.remote_ip == {198, 51, 100, 23}
    end

    test "a private client address is reported, not skipped" do
      # The real client is on an internal network; an unlisted private range
      # must not be passed over in favour of the entry the client injected.
      conn = resolve({10, 0, 4, 2}, "9.9.9.9, 192.168.7.7")
      assert conn.remote_ip == {192, 168, 7, 7}
    end

    test "skips every hop inside the configured proxies" do
      conn = resolve({10, 0, 4, 2}, "198.51.100.23, 10.0.4.9")
      assert conn.remote_ip == {198, 51, 100, 23}
    end

    test "uses the leftmost hop when every hop is a trusted proxy" do
      conn = resolve({10, 0, 4, 2}, "10.0.4.8, 10.0.4.9")
      assert conn.remote_ip == {10, 0, 4, 8}
    end

    test "an unparseable entry stops the walk at the last trusted hop" do
      conn = resolve({10, 0, 4, 2}, "9.9.9.9, garbage, 10.0.4.9")
      assert conn.remote_ip == {10, 0, 4, 9}

      conn = resolve({10, 0, 4, 2}, "9.9.9.9, unknown")
      assert conn.remote_ip == {10, 0, 4, 2}
    end

    test "keeps the peer when there is no X-Forwarded-For" do
      conn = resolve({10, 0, 4, 2}, [])
      assert conn.remote_ip == {10, 0, 4, 2}
    end

    test "joins multiple X-Forwarded-For headers in order" do
      conn = resolve({10, 0, 4, 2}, ["9.9.9.9", "198.51.100.23, 10.0.4.9"])
      assert conn.remote_ip == {198, 51, 100, 23}
    end

    test "accepts entries carrying a port" do
      assert resolve({10, 0, 4, 2}, "198.51.100.23:51234").remote_ip == {198, 51, 100, 23}

      assert resolve({10, 0, 4, 2}, "[2001:db9::5]:443").remote_ip ==
               {0x2001, 0xDB9, 0, 0, 0, 0, 0, 5}
    end

    test "treats an IPv4-mapped IPv6 peer as its IPv4 address" do
      # ::ffff:10.0.4.2, as seen when the endpoint listens on `::`.
      mapped_peer = {0, 0, 0, 0, 0, 0xFFFF, 0x0A00, 0x0402}
      conn = resolve(mapped_peer, "198.51.100.23")
      assert conn.remote_ip == {198, 51, 100, 23}
    end

    test "unmaps an IPv4-mapped forwarded address" do
      conn = resolve({10, 0, 4, 2}, "::ffff:198.51.100.23")
      assert conn.remote_ip == {198, 51, 100, 23}
    end

    test "works for IPv6 peers and proxies" do
      conn = resolve({0x2001, 0xDB8, 0, 0, 0, 0, 0, 1}, "2001:db9::5")
      assert conn.remote_ip == {0x2001, 0xDB9, 0, 0, 0, 0, 0, 5}
    end
  end

  describe "proxy configuration" do
    test "accepts a bare IP as a single-host proxy" do
      trust(["10.0.4.2"])

      assert resolve({10, 0, 4, 2}, "198.51.100.23").remote_ip == {198, 51, 100, 23}
      assert resolve({10, 0, 4, 3}, "198.51.100.23").remote_ip == {10, 0, 4, 3}
    end

    test "rejects an invalid entry with a clear error" do
      trust(["10.0.4.7/24"])

      assert_raise ArgumentError, ~r/FLUX_TRUSTED_PROXIES/, fn ->
        resolve({10, 0, 4, 2}, "198.51.100.23")
      end
    end
  end
end
