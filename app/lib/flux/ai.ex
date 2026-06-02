defmodule Flux.AI do
  @moduledoc """
  Facade over the active `Flux.AI.Provider`. All pipeline and UI code
  should route through this module rather than calling a provider
  (`Flux.AI.Detector`, `Flux.AI.Providers.Basic`, etc.) directly.
  """

  alias Flux.AI.Registry

  @spec record(Flux.AI.Provider.pipeline_id(), Flux.AI.Provider.field(), number()) :: :ok
  def record(pipeline_id, field, value), do: Registry.active().record(pipeline_id, field, value)

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
