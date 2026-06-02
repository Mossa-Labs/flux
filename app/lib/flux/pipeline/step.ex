defmodule Flux.Pipeline.Step do
  @moduledoc """
  Behaviour for pipeline transformation steps.

  Each step receives data and configuration, and returns one of:
  - `{:ok, transformed_data}` - step succeeded, continue processing
  - `{:skip, reason}` - skip this message (e.g., filtered out)
  - `{:error, reason}` - step failed, message goes to DLQ
  """

  @type data :: map()
  @type config :: map()
  @type reason :: String.t() | atom()

  @callback execute(data(), config()) ::
              {:ok, data()}
              | {:skip, reason()}
              | {:error, reason()}

  @doc """
  Returns the step module for a given operation name.

  Delegates to `Flux.Pipeline.StepRegistry`, which is populated at boot
  with Community step types and extended by EE with Pro step types.
  """
  defdelegate module_for_operation(operation), to: Flux.Pipeline.StepRegistry, as: :lookup
end
