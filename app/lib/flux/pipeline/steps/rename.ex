defmodule Flux.Pipeline.Steps.Rename do
  @moduledoc """
  Rename step for renaming fields in the data.

  Config options:
  - `from`: Original field name
  - `to`: New field name
  """

  @behaviour Flux.Pipeline.Step

  @impl true
  def execute(data, config) when is_map(data) and is_map(config) do
    from = Map.get(config, "from")
    to = Map.get(config, "to")

    cond do
      is_nil(from) or is_nil(to) ->
        {:error, "Rename step requires 'from' and 'to' in config"}

      not Map.has_key?(data, from) ->
        {:ok, data}

      true ->
        {value, rest} = Map.pop(data, from)
        {:ok, Map.put(rest, to, value)}
    end
  end

  def execute(_data, _config) do
    {:error, "Invalid data or config format"}
  end
end
