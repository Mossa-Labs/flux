defmodule Flux.Audit.Context do
  @moduledoc """
  Per-process ambient audit context (MOS-482).

  Mutating context functions run in the same process that handled the request —
  a LiveView process (mount + its event handlers) or a controller process (its
  plug pipeline). We stash the acting user and request metadata (IP, user agent,
  API-key prefix) there once, so `Flux.Audit.log/1` can fill in actor/metadata
  automatically and call sites only supply domain facts (org, action, resource,
  changes).

  Set it from `FluxWeb.UserAuth`'s LiveView `on_mount` and the API plug; anything
  running without a context (background jobs, system tasks) simply logs with
  `actor_type: :system`.
  """

  @key :flux_audit_context

  @doc "Merges `attrs` into the current process's audit context."
  @spec put(map()) :: :ok
  def put(attrs) when is_map(attrs) do
    Process.put(@key, Map.merge(get(), attrs))
    :ok
  end

  @doc "Returns the current process's audit context (empty map if unset)."
  @spec get() :: map()
  def get, do: Process.get(@key) || %{}

  @doc "Clears the current process's audit context."
  @spec clear() :: :ok
  def clear do
    Process.delete(@key)
    :ok
  end
end
