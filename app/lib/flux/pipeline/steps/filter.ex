defmodule Flux.Pipeline.Steps.Filter do
  @moduledoc """
  Filter step for keeping or dropping messages based on conditions.

  Config options:
  - `field`: Field to check (dot notation supported)
  - `operator`: Comparison operator (eq, ne, in, not_in, gt, gte, lt, lte, contains, matches)
  - `value`: Value to compare against (for single-value operators)
  - `values`: List of values (for in/not_in operators)
  """

  @behaviour Flux.Pipeline.Step

  @impl true
  def execute(data, config) when is_map(data) and is_map(config) do
    field = Map.get(config, "field")
    operator = Map.get(config, "operator")

    cond do
      is_nil(field) or is_nil(operator) ->
        {:error, "Filter step requires 'field' and 'operator' in config"}

      true ->
        field_value = get_nested(data, field)

        if matches?(field_value, operator, config) do
          {:ok, data}
        else
          {:skip, :filtered}
        end
    end
  end

  def execute(_data, _config) do
    {:error, "Invalid data or config format"}
  end

  defp get_nested(data, field) do
    field
    |> String.split(".")
    |> Enum.reduce_while(data, fn key, acc ->
      case acc do
        %{^key => value} -> {:cont, value}
        _ -> {:halt, nil}
      end
    end)
  end

  defp matches?(field_value, "eq", config), do: field_value == Map.get(config, "value")
  defp matches?(field_value, "ne", config), do: field_value != Map.get(config, "value")

  defp matches?(field_value, "in", config) do
    values = Map.get(config, "values", [])
    field_value in values
  end

  defp matches?(field_value, "not_in", config) do
    values = Map.get(config, "values", [])
    field_value not in values
  end

  defp matches?(field_value, "gt", config) when is_number(field_value) do
    value = Map.get(config, "value")
    is_number(value) and field_value > value
  end

  defp matches?(field_value, "gte", config) when is_number(field_value) do
    value = Map.get(config, "value")
    is_number(value) and field_value >= value
  end

  defp matches?(field_value, "lt", config) when is_number(field_value) do
    value = Map.get(config, "value")
    is_number(value) and field_value < value
  end

  defp matches?(field_value, "lte", config) when is_number(field_value) do
    value = Map.get(config, "value")
    is_number(value) and field_value <= value
  end

  defp matches?(field_value, "contains", config) when is_binary(field_value) do
    value = Map.get(config, "value", "")
    String.contains?(field_value, value)
  end

  defp matches?(field_value, "matches", config) when is_binary(field_value) do
    case Map.get(config, "value") do
      nil -> false
      pattern -> Regex.match?(~r/#{pattern}/, field_value)
    end
  end

  defp matches?(_field_value, _operator, _config), do: false
end
