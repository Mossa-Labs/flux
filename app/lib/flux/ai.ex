defmodule Flux.AI do
  @moduledoc """
  Facade over the active `Flux.AI.Provider`. All pipeline and UI code
  should route through this module rather than calling a provider
  (`Flux.AI.Detector`, `Flux.AI.Providers.Basic`, etc.) directly.
  """

  alias Flux.AI.Registry

  @spec record(Flux.AI.Provider.pipeline_id(), Flux.AI.Provider.field(), number()) :: :ok
  def record(pipeline_id, field, value), do: Registry.active().record(pipeline_id, field, value)

  @doc """
  Registers the detection mode + params for a pipeline. Called once at pipeline
  start. Providers that don't implement `configure/3` (e.g. the Basic stub) are
  treated as a no-op.
  """
  @spec configure(
          Flux.AI.Provider.pipeline_id(),
          Flux.AI.Provider.mode(),
          Flux.AI.Provider.mode_params()
        ) :: :ok
  def configure(pipeline_id, mode, params) do
    provider = Registry.active()

    if function_exported?(provider, :configure, 3) do
      provider.configure(pipeline_id, mode, params)
    else
      :ok
    end
  end

  @doc """
  Ingests a whole data row; the active provider extracts what it needs based on the
  pipeline's configured mode. Falls back to recording each numeric field individually
  for providers that don't implement `record_observation/2` (e.g. the Basic stub).
  """
  @spec record_observation(Flux.AI.Provider.pipeline_id(), map()) :: :ok
  def record_observation(pipeline_id, data) when is_map(data) do
    provider = Registry.active()

    if function_exported?(provider, :record_observation, 2) do
      provider.record_observation(pipeline_id, data)
    else
      for {field, value} <- data, is_number(value) do
        provider.record(pipeline_id, field, value)
      end

      :ok
    end
  end

  @spec score(Flux.AI.Provider.pipeline_id(), map(), [Flux.AI.Provider.field()]) :: {:ok, float()}
  def score(pipeline_id, data, fields), do: Registry.active().score(pipeline_id, data, fields)

  @spec list_fields(Flux.AI.Provider.pipeline_id()) :: [Flux.AI.Provider.field()]
  def list_fields(pipeline_id), do: Registry.active().list_fields(pipeline_id)

  @spec list_anomalous_pipelines(number()) :: [Flux.AI.Provider.pipeline_id()]
  def list_anomalous_pipelines(threshold \\ 2.0),
    do: Registry.active().list_anomalous_pipelines(threshold)

  @spec get_stats(Flux.AI.Provider.pipeline_id(), Flux.AI.Provider.field()) ::
          {:ok, map()} | {:error, :not_found}
  def get_stats(pipeline_id, field), do: Registry.active().get_stats(pipeline_id, field)

  @spec clear_pipeline(Flux.AI.Provider.pipeline_id()) :: :ok
  def clear_pipeline(pipeline_id), do: Registry.active().clear_pipeline(pipeline_id)
end
