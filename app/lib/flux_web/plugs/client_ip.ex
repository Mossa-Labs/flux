defmodule FluxWeb.Plugs.ClientIp do
  @moduledoc """
  Resolves `conn.remote_ip` to the real client IP.

  Trusted proxies are configured as IPs or CIDRs:

      config :flux, FluxWeb.Plugs.ClientIp, proxies: ["10.0.4.0/24", "203.0.113.7"]

  (env `FLUX_TRUSTED_PROXIES`, comma-separated).

  - **No trusted proxies configured (default):** `conn.remote_ip` stays the
    TCP peer, which is unspoofable.
  - **The TCP peer is not a trusted proxy:** `X-Forwarded-For` is ignored
    entirely and `conn.remote_ip` stays the TCP peer. A client that connects
    directly cannot choose its own IP by sending the header.
  - **The TCP peer is a trusted proxy:** `X-Forwarded-For` is walked from the
    right (the entry the nearest proxy appended) towards the left, skipping
    only addresses inside the configured proxies. The first address outside
    them is the client. If every entry is a trusted proxy, the leftmost one is
    used. An unparseable entry stops the walk and the last trusted hop is used,
    so a garbled header can never make an earlier, client-supplied entry win.

  Only the configured proxies are skipped — private and loopback ranges get no
  special treatment, so an internal client's real `10.x` address is reported
  rather than passed over in favour of whatever it put in the header. This
  relies on each trusted proxy *appending* the address it received the request
  from (nginx `$proxy_add_x_forwarded_for`), which is what common proxies do.

  IPv4-mapped IPv6 addresses (`::ffff:a.b.c.d`, as seen when the endpoint
  listens on `::`) are always rewritten to the IPv4 address they carry —
  whether or not proxies are configured — so the peer check, the IP allowlist's
  IPv4 ranges and audit logs all see `a.b.c.d`.

  Correcting `remote_ip` here benefits every downstream consumer — the IP
  allowlist, `FluxWeb.AuditMeta`, and webhook logging.
  """

  @behaviour Plug

  import Bitwise

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn = %{conn | remote_ip: unmap(conn.remote_ip)}

    case trusted_proxies() do
      [] -> conn
      proxies -> resolve(conn, proxies)
    end
  end

  defp resolve(conn, proxies) do
    peer = conn.remote_ip

    if trusted?(peer, proxies) do
      hops =
        conn
        |> Plug.Conn.get_req_header("x-forwarded-for")
        |> Enum.flat_map(&String.split(&1, ",", trim: true))

      %{conn | remote_ip: walk(Enum.reverse(hops), peer, proxies)}
    else
      conn
    end
  end

  # Right-to-left over the forwarded chain. `last_trusted` is the nearest hop
  # known to be a trusted proxy (initially the peer itself).
  defp walk([], last_trusted, _proxies), do: last_trusted

  defp walk([hop | rest], last_trusted, proxies) do
    case parse_hop(hop) do
      {:ok, ip} -> if trusted?(ip, proxies), do: walk(rest, ip, proxies), else: ip
      :error -> last_trusted
    end
  end

  defp trusted?(ip, proxies), do: Enum.any?(proxies, &InetCidr.contains?(&1, ip))

  # Accepts a bare IPv4/IPv6 address, `a.b.c.d:port`, `[v6]` or `[v6]:port`
  # (some load balancers include the source port).
  defp parse_hop(hop) do
    hop
    |> String.trim()
    |> strip_port()
    |> String.to_charlist()
    |> :inet.parse_strict_address()
    |> case do
      {:ok, ip} -> {:ok, unmap(ip)}
      {:error, _} -> :error
    end
  end

  defp strip_port("[" <> rest) do
    case String.split(rest, "]", parts: 2) do
      [addr, ""] -> addr
      [addr, ":" <> _port] -> addr
      _ -> ""
    end
  end

  defp strip_port(hop) do
    case String.split(hop, ":") do
      [v4, _port] -> v4
      _ -> hop
    end
  end

  defp unmap({0, 0, 0, 0, 0, 0xFFFF, ab, cd}), do: {ab >>> 8, ab &&& 0xFF, cd >>> 8, cd &&& 0xFF}
  defp unmap(ip), do: ip

  # Parsed proxy blocks, cached in :persistent_term keyed by the configured
  # list (so a config change is picked up automatically).
  defp trusted_proxies do
    proxies = Application.get_env(:flux, __MODULE__, [])[:proxies] || []
    key = {__MODULE__, :proxies, proxies}

    case :persistent_term.get(key, :unset) do
      :unset ->
        parsed = Enum.map(proxies, &parse_proxy!/1)
        :persistent_term.put(key, parsed)
        parsed

      parsed ->
        parsed
    end
  end

  defp parse_proxy!(entry) do
    entry = String.trim(entry)
    cidr = if String.contains?(entry, "/"), do: entry, else: entry <> host_prefix(entry)

    case InetCidr.parse_cidr(cidr) do
      {:ok, block} ->
        block

      {:error, _} ->
        raise ArgumentError,
              "invalid trusted proxy #{inspect(entry)} in FLUX_TRUSTED_PROXIES — " <>
                "expected an IP address or a CIDR whose address is the network base " <>
                ~s|(e.g. "10.0.4.0/24", not "10.0.4.7/24")|
    end
  end

  defp host_prefix(entry), do: if(String.contains?(entry, ":"), do: "/128", else: "/32")
end
