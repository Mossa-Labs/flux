defmodule Flux.AI.Providers.Basic do
  @moduledoc """
  Stateless no-op AI provider shipped with Community builds.

  Advanced anomaly detection (sliding-window z-score, IQR, Nx batch
  scoring) is a Pro feature of the commercial Flux Pro edition.
  Basic is safe to call from any pipeline code: `record/3` and `score/3`
  succeed trivially; list/stats calls return empty results.
  """

  @behaviour Flux.AI.Provider

  @impl Flux.AI.Provider
  def record(_pipeline_id, _field, _value), do: :ok

  @impl Flux.AI.Provider
  def score(_pipeline_id, _data, _fields), do: {:ok, 0.0}

  @impl Flux.AI.Provider
  def list_fields(_pipeline_id), do: []

  @impl Flux.AI.Provider
  def list_anomalous_pipelines(_threshold), do: []

  @impl Flux.AI.Provider
  def get_stats(_pipeline_id, _field), do: {:error, :not_found}

  @impl Flux.AI.Provider
  def clear_pipeline(_pipeline_id), do: :ok
end
