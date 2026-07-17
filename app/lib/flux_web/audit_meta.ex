defmodule FluxWeb.AuditMeta do
  @moduledoc """
  Extracts request metadata (IP address, user agent) for audit events (MOS-482).

  `from_conn/1` works in the plug/controller pipeline; `from_socket/1` reads a
  connected LiveView's `connect_info` (only available once the socket is
  connected — the caller should guard with `connected?/1`). Both return a
  string-keyed map suitable for the audit `metadata` column, with blank keys
  dropped.
  """

  import Plug.Conn, only: [get_req_header: 2]

  @doc "Request metadata from a `Plug.Conn`."
  @spec from_conn(Plug.Conn.t()) :: map()
  def from_conn(%Plug.Conn{} = conn) do
    build(format_ip(conn.remote_ip), header(conn, "user-agent"))
  end

  @doc "Request metadata from a connected LiveView socket via `connect_info`."
  @spec from_socket(Phoenix.LiveView.Socket.t()) :: map()
  def from_socket(socket) do
    ip =
      case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
        %{address: address} -> format_ip(address)
        _ -> nil
      end

    build(ip, Phoenix.LiveView.get_connect_info(socket, :user_agent))
  end

  defp build(ip, user_agent) do
    %{"ip_address" => ip, "user_agent" => user_agent}
    |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
    |> Map.new()
  end

  defp header(conn, name) do
    case get_req_header(conn, name) do
      [value | _] -> value
      _ -> nil
    end
  end

  defp format_ip(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> to_string()
  defp format_ip(ip) when is_binary(ip), do: ip
  defp format_ip(_), do: nil
end
