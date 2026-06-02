defmodule Flux.AI.Provider do
  @moduledoc """
  Contract for AI / anomaly-detection providers.

  Community ships `Flux.AI.Providers.Basic` (stateless no-op that reports
  no anomalies — advanced detection is a Pro feature). EE ships
  `Flux.AI.Detector`-backed providers with sliding-window z-score,
  IQR, and Nx-accelerated batch scoring.

  Callers should use the `Flux.AI` facade, which resolves the active
  provider via `Flux.AI.Registry`.
  """

  @type pipeline_id :: String.t() | integer()
  @type field :: String.t()
  @type data :: map()
  @type stats :: map()

  @callback record(pipeline_id(), field(), number()) :: :ok

  @callback score(pipeline_id(), data(), [field()]) :: {:ok, float()}

  @callback list_fields(pipeline_id()) :: [field()]

  @callback list_anomalous_pipelines(threshold :: number()) :: [pipeline_id()]

  @callback get_stats(pipeline_id(), field()) :: {:ok, stats()} | {:error, :not_found}

  @callback clear_pipeline(pipeline_id()) :: :ok

  @doc """
  Optional: returns a child spec for the supervision tree if this provider
  requires a long-lived process (e.g., ETS owner). Community's Basic
  provider has no process and does not implement this callback.
  """
  @callback child_spec(opts :: keyword()) :: Supervisor.child_spec() | nil

  @optional_callbacks [child_spec: 1]
end
