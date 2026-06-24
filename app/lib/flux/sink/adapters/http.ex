defmodule Flux.Sink.Adapters.HTTP do
  @moduledoc """
  HTTP webhook sink adapter using Req.

  Delivers pipeline data to HTTP endpoints as JSON payloads.

  ## Configuration

      %{
        "type" => "http",
        "url" => "https://example.com/webhook",      # Required
        "method" => "POST",                          # Optional, default: "POST"
        "headers" => %{"X-Custom" => "value"},       # Optional
        "auth" => %{                                 # Optional
          "type" => "bearer",                        # "bearer", "basic", or "api_key"
          "token" => "secret"                        # For bearer auth
        },
        "retry" => %{                                # Optional
          "max_attempts" => 3,                       # Default: 3
          "delay_ms" => 1000                         # Default: 1000
        },
        "timeout_ms" => 30000                        # Optional, default: 30000
      }

  ## Authentication Types

  - **bearer**: Uses `Authorization: Bearer <token>` header
  - **basic**: Uses `Authorization: Basic <base64(username:password)>` header
  - **api_key**: Adds a custom header with the API key

  """

  @behaviour Flux.Sink.Adapter

  require Logger

  @default_timeout 30_000
  @default_max_attempts 3
  @default_delay 1_000

  @impl Flux.Sink.Adapter
  def deliver(data, config, _opts) do
    url = Map.fetch!(config, "url")
    method = normalize_method(Map.get(config, "method", "POST"))
    headers = build_headers(config)
    timeout = Map.get(config, "timeout_ms", @default_timeout)
    retry_config = Map.get(config, "retry", %{})

    req_opts =
      [
        method: method,
        url: url,
        headers: headers,
        json: data,
        receive_timeout: timeout
      ] ++ build_retry_opts(retry_config)

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        Logger.debug("HTTP sink delivered successfully",
          url: url,
          status: status
        )

        {:ok, %{status: status, body: body}}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("HTTP sink received non-2xx response",
          url: url,
          status: status
        )

        {:error, {:http_error, status, body}}

      {:error, %Req.TransportError{reason: reason}} ->
        Logger.error("HTTP sink transport error",
          url: url,
          reason: inspect(reason)
        )

        {:error, {:transport_error, reason}}

      {:error, reason} ->
        Logger.error("HTTP sink delivery failed",
          url: url,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  # Maps known HTTP verbs (case-insensitively) to the lowercase atoms Req expects.
  # Built statically so user-supplied config can never intern arbitrary atoms;
  # anything unrecognized falls back to :post (config is screened by
  # `validate_config/1` before it reaches here).
  @methods %{
    "get" => :get,
    "post" => :post,
    "put" => :put,
    "patch" => :patch,
    "delete" => :delete
  }

  defp normalize_method(method) when is_binary(method) do
    Map.get(@methods, String.downcase(method), :post)
  end

  defp normalize_method(_method), do: :post

  @impl Flux.Sink.Adapter
  def validate_config(config) do
    Flux.Sink.Validation.run(config, [
      &validate_url/1,
      &validate_method/1,
      &validate_auth/1
    ])
  end

  defp validate_url(config) do
    case Map.get(config, "url") do
      nil ->
        {:error, "url is required"}

      url when is_binary(url) ->
        case URI.parse(url) do
          %URI{scheme: scheme} when scheme in ["http", "https"] -> :ok
          _ -> {:error, "url must be a valid HTTP/HTTPS URL"}
        end

      _ ->
        {:error, "url must be a string"}
    end
  end

  defp validate_method(config) do
    case Map.get(config, "method") do
      nil ->
        :ok

      method when is_binary(method) ->
        if is_map_key(@methods, String.downcase(method)) do
          :ok
        else
          {:error, "method must be GET, POST, PUT, PATCH, or DELETE"}
        end

      _ ->
        {:error, "method must be a string"}
    end
  end

  defp validate_auth(config) do
    case Map.get(config, "auth") do
      nil ->
        :ok

      %{"type" => "bearer", "token" => token} when is_binary(token) ->
        :ok

      %{"type" => "basic", "username" => u, "password" => p}
      when is_binary(u) and is_binary(p) ->
        :ok

      %{"type" => "api_key", "header_name" => h, "key" => k}
      when is_binary(h) and is_binary(k) ->
        :ok

      %{"type" => type} ->
        {:error, "auth type '#{type}' requires proper configuration"}

      _ ->
        {:error, "auth must have a valid type (bearer, basic, or api_key)"}
    end
  end

  @impl Flux.Sink.Adapter
  def test_connection(config) do
    url = Map.fetch!(config, "url")

    case Req.head(url, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: status}} when status in 200..499 ->
        :ok

      {:ok, %Req.Response{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Builds the request header list from a sink config: a JSON content-type, any
  user-supplied `headers`, and the auth header for the configured `auth` block
  (`bearer`, `basic`, or `api_key`). Pure — unit-tested without a network call.
  """
  @spec build_headers(map()) :: [{String.t(), String.t()}]
  def build_headers(config) do
    base_headers = [{"content-type", "application/json"}]
    custom_headers = config |> Map.get("headers", %{}) |> Map.to_list()
    auth_headers = build_auth_headers(Map.get(config, "auth"))

    base_headers ++ custom_headers ++ auth_headers
  end

  defp build_auth_headers(nil), do: []

  defp build_auth_headers(%{"type" => "bearer", "token" => token}) do
    [{"authorization", "Bearer #{token}"}]
  end

  defp build_auth_headers(%{"type" => "basic", "username" => user, "password" => pass}) do
    encoded = Base.encode64("#{user}:#{pass}")
    [{"authorization", "Basic #{encoded}"}]
  end

  defp build_auth_headers(%{"type" => "api_key", "header_name" => header, "key" => key}) do
    [{String.downcase(header), key}]
  end

  defp build_auth_headers(_), do: []

  defp build_retry_opts(config) do
    max_attempts = Map.get(config, "max_attempts", @default_max_attempts)
    delay = Map.get(config, "delay_ms", @default_delay)

    [
      retry: :transient,
      max_retries: max_attempts - 1,
      retry_delay: fn _count -> delay end,
      retry_log_level: :warning
    ]
  end
end
