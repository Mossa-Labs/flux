defmodule Flux.Source do
  @moduledoc """
  Facade for source adapters. The adapter contract lives in
  `Flux.Source.Adapter`.

  Sources bring events from external systems into Flux's internal queue.
  Adapters are registered at boot against a string type identifier in
  `Flux.Source.Registry`; this facade looks up the adapter for a configured
  type and delegates.

  ## Usage

      # The internal queue a pipeline consumes for a webhook source
      "webhooks.github" = Flux.Source.queue_name("webhook", %{"source" => "github"})

      # Validate source configuration
      :ok = Flux.Source.validate_config("webhook", %{"source" => "github"})

  """

  require Logger

  @type source_config :: Flux.Source.Adapter.source_config()
  @type validation_result :: Flux.Source.Adapter.validation_result()

  @doc """
  Returns the adapter module for a given source type.

  ## Examples

      {:ok, Flux.Source.Adapters.Webhook} = Flux.Source.adapter_for_type("webhook")
      {:error, :unknown_type} = Flux.Source.adapter_for_type("invalid")

  """
  @spec adapter_for_type(String.t() | atom()) :: {:ok, module()} | {:error, :unknown_type}
  defdelegate adapter_for_type(type), to: Flux.Source.Registry, as: :lookup

  @doc "Lists all available source types."
  @spec available_types() :: [String.t()]
  defdelegate available_types(), to: Flux.Source.Registry, as: :list

  @doc """
  Returns the internal queue name a pipeline should consume for this source.

  Returns `{:error, {:unknown_source_type, type}}` if the type is not registered.
  """
  @spec queue_name(String.t(), source_config()) ::
          String.t() | {:error, {:unknown_source_type, String.t()}}
  def queue_name(type, config) do
    case adapter_for_type(type) do
      {:ok, adapter} -> adapter.queue_name(config)
      {:error, :unknown_type} -> {:error, {:unknown_source_type, type}}
    end
  end

  @doc """
  Returns the long-lived ingestion child spec for a source, or `nil` for passive
  sources (webhook, poll) and unknown types.

  `opts` carries runtime context such as `:source_id` and `:organization_id`.
  """
  @spec ingestion_spec(String.t(), source_config(), keyword()) :: Supervisor.child_spec() | nil
  def ingestion_spec(type, config, opts \\ []) do
    case adapter_for_type(type) do
      {:ok, adapter} ->
        if exported?(adapter, :ingestion_spec, 2) do
          adapter.ingestion_spec(config, opts)
        else
          nil
        end

      {:error, :unknown_type} ->
        nil
    end
  end

  @doc """
  Validates source configuration for a given type.

  ## Examples

      :ok = Flux.Source.validate_config("webhook", %{"source" => "github"})
      {:error, ["source is required"]} = Flux.Source.validate_config("webhook", %{})

  """
  @spec validate_config(String.t(), source_config()) :: validation_result()
  def validate_config(type, config) do
    case adapter_for_type(type) do
      {:ok, adapter} -> adapter.validate_config(config)
      {:error, :unknown_type} -> {:error, ["unknown source type: #{type}"]}
    end
  end

  @doc """
  Tests connectivity to a source.

  Returns `:ok` if the connection is successful, or `{:error, reason}` if not.
  Passive sources that do not implement `test_connection/1` return `:ok`.
  """
  @spec test_connection(String.t(), source_config()) :: :ok | {:error, term()}
  def test_connection(type, config) do
    case adapter_for_type(type) do
      {:ok, adapter} ->
        if exported?(adapter, :test_connection, 1) do
          adapter.test_connection(config)
        else
          :ok
        end

      {:error, :unknown_type} ->
        {:error, {:unknown_source_type, type}}
    end
  end

  # `function_exported?/3` returns false for a module that has not been loaded
  # yet (common for adapter modules referenced only by atom in the registry), so
  # ensure it is loaded before probing for an optional callback.
  defp exported?(module, fun, arity) do
    Code.ensure_loaded?(module) and function_exported?(module, fun, arity)
  end
end
