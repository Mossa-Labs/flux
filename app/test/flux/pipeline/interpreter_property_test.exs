defmodule Flux.Pipeline.InterpreterPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Flux.Pipeline.Interpreter

  # Generators

  defp data_generator do
    map_of(
      string(:alphanumeric, min_length: 1, max_length: 10),
      one_of([string(:alphanumeric), integer(), float(), boolean()]),
      min_length: 1,
      max_length: 5
    )
  end

  defp step_generator do
    one_of([
      rename_step_generator(),
      filter_step_generator(),
      map_step_generator()
    ])
  end

  defp rename_step_generator do
    gen all(
          from <- string(:alphanumeric, min_length: 1, max_length: 5),
          to <- string(:alphanumeric, min_length: 1, max_length: 5)
        ) do
      %{"type" => "native", "operation" => "rename", "config" => %{"from" => from, "to" => to}}
    end
  end

  defp filter_step_generator do
    gen all(
          field <- string(:alphanumeric, min_length: 1, max_length: 5),
          operator <- member_of(~w(eq ne)),
          value <- string(:alphanumeric, min_length: 1, max_length: 5)
        ) do
      %{
        "type" => "native",
        "operation" => "filter",
        "config" => %{"field" => field, "operator" => operator, "value" => value}
      }
    end
  end

  defp map_step_generator do
    gen all(
          field <- string(:alphanumeric, min_length: 1, max_length: 5),
          to <- string(:alphanumeric, min_length: 1, max_length: 5)
        ) do
      %{"type" => "native", "operation" => "map", "config" => %{"field" => field, "to" => to}}
    end
  end

  # Properties

  property "empty steps returns original data" do
    check all(data <- data_generator()) do
      config = %{"version" => "1.0", "steps" => []}
      assert {:ok, ^data} = Interpreter.execute(data, config)
    end
  end

  property "multi-step pipelines always return valid result tuples" do
    check all(
            data <- data_generator(),
            steps <- list_of(step_generator(), max_length: 3)
          ) do
      config = %{"version" => "1.0", "steps" => steps}
      result = Interpreter.execute(data, config)
      assert match?({:ok, _}, result) or match?({:skip, _}, result) or match?({:error, _}, result)
    end
  end
end
