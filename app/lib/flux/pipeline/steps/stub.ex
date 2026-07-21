defmodule Flux.Pipeline.Steps.Stub do
  @moduledoc """
  Placeholder pipeline step registered against Enterprise-only operations in
  Community builds (currently the `redact` / `classify` PII steps, MOS-480).

  Unlike the sink/source/queue stubs — which return a structured
  `{:error, {:pro_required, feature}}` because a *delivery* has nowhere to go —
  a pipeline step sits inline in a running pipeline. Failing it closed would
  halt every message of an imported Enterprise pipeline the moment it reached a
  Community node. So the stub **passes data through unchanged** (`{:ok, data}`),
  matching the fail-open convention of the `anomaly_detect` gate in
  `Flux.Pipeline.Interpreter`, and logs a single warning per operation so the
  gap is visible in the logs without spamming per-message.

  The Enterprise edition overlays the real implementations
  (`Flux.Pipeline.Steps.Redact` / `Flux.Pipeline.Steps.Classify`) over these
  registrations at boot, gated on `:pii_redaction`.
  """

  @behaviour Flux.Pipeline.Step

  require Logger

  @impl Flux.Pipeline.Step
  def execute(data, config) when is_map(data) and is_map(config) do
    warn_once()
    {:ok, data}
  end

  def execute(data, _config), do: {:ok, data}

  # Emits a single warning per node so an unlicensed pipeline flags the skipped
  # Enterprise step once, not once per message. (The interpreter passes only the
  # step's `config`, so the concrete operation name is not available here.)
  defp warn_once do
    key = {__MODULE__, :warned}

    if :persistent_term.get(key, false) do
      :ok
    else
      :persistent_term.put(key, true)

      Logger.warning(
        "[Flux.Pipeline.Steps.Stub] Skipping an Enterprise pipeline step " <>
          "(redact/classify) — requires the :pii_redaction feature. " <>
          "Data is passing through unredacted on this Community build."
      )
    end
  end
end
