defmodule Flux.Pipeline.Steps.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Flux.Pipeline.Steps.{Filter, Map, Rename}

  # Generators

  defp data_generator do
    map_of(
      string(:alphanumeric, min_length: 1, max_length: 10),
      one_of([string(:alphanumeric), integer(), float(), boolean()]),
      min_length: 1,
      max_length: 5
    )
  end

  # Properties

  property "filter is idempotent" do
    check all(data <- data_generator()) do
      {field, value} = data |> Enum.to_list() |> hd()
      config = %{"field" => field, "operator" => "eq", "value" => value}
      result1 = Filter.execute(data, config)

      case result1 do
        {:ok, filtered_data} ->
          assert Filter.execute(filtered_data, config) == result1

        {:skip, :filtered} ->
          :ok
      end
    end
  end

  property "rename roundtrip preserves data" do
    check all(
            data <- data_generator(),
            new_name <- string(:alphanumeric, min_length: 1, max_length: 10)
          ) do
      {original_key, _} = data |> Enum.to_list() |> hd()

      if not Elixir.Map.has_key?(data, new_name) and original_key != new_name do
        {:ok, renamed} = Rename.execute(data, %{"from" => original_key, "to" => new_name})
        {:ok, restored} = Rename.execute(renamed, %{"from" => new_name, "to" => original_key})
        assert restored == data
      end
    end
  end

  property "map step only adds keys, never removes" do
    check all(
            data <- data_generator(),
            to_field <- string(:alphanumeric, min_length: 1, max_length: 10)
          ) do
      {field, _} = data |> Enum.to_list() |> hd()
      config = %{"field" => field, "to" => to_field}
      {:ok, result} = Map.execute(data, config)

      for key <- Elixir.Map.keys(data) do
        assert Elixir.Map.has_key?(result, key)
      end
    end
  end

  property "filter never crashes on well-formed input" do
    check all(
            data <- data_generator(),
            field <- string(:alphanumeric, min_length: 1, max_length: 10),
            operator <- member_of(~w(eq ne gt gte lt lte contains)),
            value <- one_of([string(:alphanumeric), integer()])
          ) do
      config = %{"field" => field, "operator" => operator, "value" => value}
      result = Filter.execute(data, config)
      assert match?({:ok, _}, result) or match?({:skip, _}, result) or match?({:error, _}, result)
    end
  end
end
