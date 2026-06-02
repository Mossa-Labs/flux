defmodule FluxWeb.Plugs.ApiAuth do
  @moduledoc """
  Plug for API key authentication.

  Validates the `X-API-Key` header against a configured API key.

  ## Configuration

      config :flux, FluxWeb.Plugs.ApiAuth,
        api_key: "your-secret-api-key"

  ## Usage

      pipeline :api_authenticated do
        plug :accepts, ["json"]
        plug FluxWeb.Plugs.ApiAuth
      end

  """

  import Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with {:ok, provided_key} <- get_api_key(conn),
         {:ok, configured_key} <- get_configured_key(),
         :ok <- validate_key(provided_key, configured_key) do
      conn
    else
      {:error, :missing_key} ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{
          error: "Missing API key",
          message: "X-API-Key header is required"
        })
        |> halt()

      {:error, :invalid_key} ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{
          error: "Invalid API key",
          message: "The provided API key is invalid"
        })
        |> halt()

      {:error, :not_configured} ->
        conn
        |> put_status(:internal_server_error)
        |> Phoenix.Controller.json(%{
          error: "Configuration error",
          message: "API authentication not configured"
        })
        |> halt()
    end
  end

  defp get_api_key(conn) do
    case get_req_header(conn, "x-api-key") do
      [key | _] when byte_size(key) > 0 -> {:ok, key}
      _ -> {:error, :missing_key}
    end
  end

  defp get_configured_key do
    case Application.get_env(:flux, __MODULE__)[:api_key] do
      nil -> {:error, :not_configured}
      key when is_binary(key) and byte_size(key) > 0 -> {:ok, key}
      _ -> {:error, :not_configured}
    end
  end

  defp validate_key(provided, configured) do
    if Plug.Crypto.secure_compare(provided, configured) do
      :ok
    else
      {:error, :invalid_key}
    end
  end
end
