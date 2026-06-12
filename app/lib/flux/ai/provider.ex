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

  @typedoc """
  Detection mode for a pipeline. `:numeric` is the baseline rolling z-score.
  `:seasonal`, `:multivariate`, and `:categorical` are advanced (Pro) modes
  implemented by EE providers; Community's Basic provider treats all modes the
  same (no-op) since advanced detection is a Pro feature.
  """
  @type mode :: :numeric | :seasonal | :multivariate | :categorical
  @type mode_params :: map()

  @callback record(pipeline_id(), field(), number()) :: :ok

  @callback score(pipeline_id(), data(), [field()]) :: {:ok, float()}

  @callback list_fields(pipeline_id()) :: [field()]

  @callback list_anomalous_pipelines(threshold :: number()) :: [pipeline_id()]

  @callback get_stats(pipeline_id(), field()) :: {:ok, stats()} | {:error, :not_found}

  @callback clear_pipeline(pipeline_id()) :: :ok

  @doc """
  Optional: registers the detection mode + mode-specific params for a pipeline.

  Called once when a pipeline starts (from the runner) with the config carried in
  the pipeline's `anomaly_detect` step. The provider keeps this and uses it to
  decide how to ingest observations and which scorer to dispatch to. Providers
  that only support the baseline may ignore it. Community's Basic provider no-ops.
  """
  @callback configure(pipeline_id(), mode(), mode_params()) :: :ok

  @doc """
  Optional: ingests a whole data row, letting the provider decide what to extract
  based on the configured mode (numeric per-field windows, categorical strings, or
  a joint multivariate feature vector). Replaces the caller having to know the mode.

  Providers without a configured mode for the pipeline should do nothing. Community's
  Basic provider no-ops.
  """
  @callback record_observation(pipeline_id(), data()) :: :ok

  @doc """
  Optional: returns a child spec for the supervision tree if this provider
  requires a long-lived process (e.g., ETS owner). Community's Basic
  provider has no process and does not implement this callback.
  """
  @callback child_spec(opts :: keyword()) :: Supervisor.child_spec() | nil

  @optional_callbacks [child_spec: 1, configure: 3, record_observation: 2]
end
