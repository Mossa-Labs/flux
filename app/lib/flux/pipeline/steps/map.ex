defmodule Flux.Pipeline.Steps.Map do
  @moduledoc """
  Map step for extracting and transforming fields.

  Config options:
  - `field`: Source field path (dot notation, e.g., "data.user.name")
  - `to`: Target field name
  - `default`: Default value if source is nil (optional)
  """

  @behaviour Flux.Pipeline.Step

  @impl true
  def execute(data, config) when is_map(data) and is_map(config) do
    field = Map.get(config, "field")
    to = Map.get(config, "to")
    default = Map.get(config, "default")

    cond do
      is_nil(field) or is_nil(to) ->
        {:error, "Map step requires 'field' and 'to' in config"}

      true ->
        value = get_nested(data, field, default)
        {:ok, Map.put(data, to, value)}
    end
  end

  def execute(_data, _config) do
    {:error, "Invalid data or config format"}
  end

  defp get_nested(data, field, default) do
    field
    |> String.split(".")
    |> Enum.reduce_while(data, fn key, acc ->
      case acc do
        %{^key => value} -> {:cont, value}
        _ -> {:halt, default}
      end
    end)
  end
end
