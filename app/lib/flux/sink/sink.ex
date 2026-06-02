defmodule Flux.Sink do
  @moduledoc """
  Facade for sink adapters. The adapter contract lives in `Flux.Sink.Adapter`.

  Sinks are output destinations for processed pipeline data. Adapters are
  registered at boot against a string type identifier in
  `Flux.Sink.Registry`; `deliver/3` looks up the adapter for the configured
  type and delegates.

  ## Usage

      # Deliver data to a sink
      config = %{"type" => "http", "url" => "https://example.com/webhook"}
      :ok = Flux.Sink.deliver(%{event: "test"}, config)

      # Validate sink configuration
      :ok = Flux.Sink.validate_config("http", config)

  """

  require Logger

  @type data :: Flux.Sink.Adapter.data()
  @type sink_config :: Flux.Sink.Adapter.sink_config()
  @type delivery_opts :: Flux.Sink.Adapter.delivery_opts()
  @type result :: Flux.Sink.Adapter.result()
  @type validation_result :: Flux.Sink.Adapter.validation_result()

  @doc """
  Returns the adapter module for a given sink type.

  ## Examples

      {:ok, Flux.Sink.Adapters.HTTP} = Flux.Sink.adapter_for_type("http")
      {:error, :unknown_type} = Flux.Sink.adapter_for_type("invalid")

  """
  @spec adapter_for_type(String.t() | atom()) :: {:ok, module()} | {:error, :unknown_type}
  defdelegate adapter_for_type(type), to: Flux.Sink.Registry, as: :lookup

  @doc """
  Lists all available sink types.
  """
  @spec available_types() :: [String.t()]
  defdelegate available_types(), to: Flux.Sink.Registry, as: :list

  @doc """
  Delivers data using the appropriate adapter based on sink config.

  The config must include a `"type"` key specifying the sink type.

  ## Examples

      config = %{"type" => "http", "url" => "https://example.com/webhook"}
      :ok = Flux.Sink.deliver(%{event: "test"}, config)

  """
  @spec deliver(data(), sink_config(), delivery_opts()) :: result()
  def deliver(data, config, opts \\ [])

  def deliver(data, %{"type" => type} = config, opts) do
    case adapter_for_type(type) do
      {:ok, adapter} ->
        Logger.debug("Delivering to #{type} sink")
        adapter.deliver(data, config, opts)

      {:error, :unknown_type} ->
        {:error, {:unknown_sink_type, type}}
    end
  end

  def deliver(_data, config, _opts) do
    {:error, {:missing_type, config}}
  end

  @doc """
  Validates sink configuration for a given type.

  ## Examples

      :ok = Flux.Sink.validate_config("http", %{"url" => "https://example.com"})
      {:error, ["url is required"]} = Flux.Sink.validate_config("http", %{})

  """
  @spec validate_config(String.t(), sink_config()) :: validation_result()
  def validate_config(type, config) do
    case adapter_for_type(type) do
      {:ok, adapter} -> adapter.validate_config(config)
      {:error, :unknown_type} -> {:error, ["unknown sink type: #{type}"]}
    end
  end

  @doc """
  Tests connectivity to a sink.

  Returns `:ok` if the connection is successful, or `{:error, reason}` if not.
  """
  @spec test_connection(String.t(), sink_config()) :: :ok | {:error, term()}
  def test_connection(type, config) do
    case adapter_for_type(type) do
      {:ok, adapter} ->
        if function_exported?(adapter, :test_connection, 1) do
          adapter.test_connection(config)
        else
          :ok
        end

      {:error, :unknown_type} ->
        {:error, {:unknown_sink_type, type}}
    end
  end
end
