defmodule Flux.Pipeline.Supervision do
  @moduledoc """
  Seam over pipeline process supervision and registration.

  The Community (`:flux`) build uses `Flux.Pipeline.Supervision.Local` — a plain
  `Registry` + `DynamicSupervisor`, single node only. The Pro build (`flux_pro`)
  swaps in a Horde-backed distributed implementation by overriding the config:

      config :flux, Flux.Pipeline.Supervision, impl: Flux.Pipeline.Supervision.Distributed

  This mirrors how `Flux.License` resolves its provider from config. Because the
  Community artifact has no clustering dependency at all, horizontal scaling / HA
  is a paid capability that cannot be unlocked by patching a license check.
  """

  @type pipeline_id :: term()
  @type via :: {:via, module(), term()}

  @doc "Cluster-or-local unique name for a pipeline runner."
  @callback via_tuple(pipeline_id()) :: via()

  @doc "Derives a per-stage name from a runner's via-tuple (Broadway `process_name/2`)."
  @callback child_via(via(), term()) :: via()

  @doc "Starts a pipeline runner child. Idempotent: an already-started runner is `{:ok, pid}`."
  @callback start_pipeline(Supervisor.child_spec() | map()) :: {:ok, pid()} | {:error, term()}

  @doc "Terminates a running pipeline runner by pid."
  @callback terminate_pipeline(pid()) :: :ok | {:error, term()}

  @doc "Returns the runner pid for a pipeline, or nil if not running."
  @callback whereis(pipeline_id()) :: pid() | nil

  @doc "Lists currently running pipeline ids."
  @callback list_running() :: [pipeline_id()]

  @doc "Number of nodes participating in supervision (1 for the local backend)."
  @callback member_count() :: pos_integer()

  @doc """
  Whether the supervision backend is ready to start runners.

  Defaults to `true`. The distributed backend uses this to make pipeline
  auto-start wait until its cluster infrastructure is up (see `Flux.Pipeline.Manager`).
  """
  @callback ready?() :: boolean()

  @optional_callbacks ready?: 0

  @doc "The active supervision implementation module."
  @spec impl() :: module()
  def impl do
    Application.get_env(:flux, __MODULE__, [])[:impl] || Flux.Pipeline.Supervision.Local
  end

  @spec via_tuple(pipeline_id()) :: via()
  def via_tuple(pipeline_id), do: impl().via_tuple(pipeline_id)

  @spec child_via(via(), term()) :: via()
  def child_via(via, base_name), do: impl().child_via(via, base_name)

  @spec start_pipeline(Supervisor.child_spec() | map()) :: {:ok, pid()} | {:error, term()}
  def start_pipeline(child_spec), do: impl().start_pipeline(child_spec)

  @spec terminate_pipeline(pid()) :: :ok | {:error, term()}
  def terminate_pipeline(pid), do: impl().terminate_pipeline(pid)

  @spec whereis(pipeline_id()) :: pid() | nil
  def whereis(pipeline_id), do: impl().whereis(pipeline_id)

  @spec list_running() :: [pipeline_id()]
  def list_running, do: impl().list_running()

  @spec member_count() :: pos_integer()
  def member_count, do: impl().member_count()

  @spec ready?() :: boolean()
  def ready? do
    mod = impl()
    if function_exported?(mod, :ready?, 0), do: mod.ready?(), else: true
  end
end
