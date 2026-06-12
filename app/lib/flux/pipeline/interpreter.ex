defmodule Flux.Pipeline.Interpreter do
  @moduledoc """
  Interprets and executes pipeline JSON IR configurations.

  The JSON IR format:
  ```json
  {
    "version": "1.0",
    "steps": [
      {"id": "s1", "type": "native", "operation": "rename", "config": {...}},
      {"id": "s2", "type": "script", "language": "lua", "code": "...", "timeout_ms": 5000},
      {"id": "s3", "type": "ai", "operation": "anomaly_detect", "config": {...}}
    ]
  }
  ```
  """

  alias Flux.Pipeline.Step
  alias Flux.Pipeline.Steps.Script

  require Logger

  @doc """
  Executes all steps in a pipeline configuration against the given data.

  Returns `{:ok, transformed_data}`, `{:skip, reason}`, or `{:error, reason}`.
  """
  def execute(data, %{"steps" => steps}) when is_list(steps) do
    execute_steps(data, steps)
  end

  def execute(data, %{}) do
    {:ok, data}
  end

  def execute(_data, _invalid) do
    {:error, "Invalid pipeline configuration"}
  end

  defp execute_steps(data, []) do
    {:ok, data}
  end

  defp execute_steps(data, [step | rest]) do
    case execute_step(data, step) do
      {:ok, transformed_data} ->
        execute_steps(transformed_data, rest)

      {:skip, reason} ->
        {:skip, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_step(data, %{"type" => "native", "operation" => operation, "config" => config}) do
    case Step.module_for_operation(operation) do
      {:ok, module} ->
        module.execute(data, config)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_step(data, %{"type" => "native", "operation" => operation}) do
    execute_step(data, %{"type" => "native", "operation" => operation, "config" => %{}})
  end

  defp execute_step(data, %{"type" => "script", "language" => "lua", "code" => code} = step) do
    timeout = Map.get(step, "timeout_ms", 5000)
    Script.execute(data, %{"code" => code, "timeout_ms" => timeout})
  end

  defp execute_step(data, %{"type" => "ai", "operation" => "anomaly_detect"} = step) do
    if Flux.License.has_feature?(:advanced_ai) do
      run_anomaly_detect(data, Map.get(step, "config", %{}))
    else
      # Community tier: skip anomaly detection and pass data through unchanged
      # so unlicensed pipelines still run.
      {:ok, data}
    end
  end

  defp execute_step(_data, %{"type" => type}) do
    {:error, "Unknown step type: #{type}"}
  end

  defp execute_step(_data, step) do
    {:error, "Invalid step format: #{inspect(step)}"}
  end

  defp run_anomaly_detect(data, config) do
    fields = parse_fields(Map.get(config, "fields", []))
    threshold = Map.get(config, "threshold", 2.0)
    pipeline_id = Map.get(config, "pipeline_id")

    case Flux.AI.score(pipeline_id, data, fields) do
      {:ok, score} when score > threshold ->
        {:ok, Map.put(data, "_anomaly", %{"score" => score, "threshold" => threshold})}

      {:ok, _score} ->
        {:ok, data}

      {:error, reason} ->
        Logger.warning("Anomaly detection failed: #{inspect(reason)}")
        {:ok, data}
    end
  end

  # The builder stores `fields` as a comma-separated string; the scorer needs a list.
  defp parse_fields(fields) when is_list(fields), do: fields

  defp parse_fields(fields) when is_binary(fields) do
    fields |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp parse_fields(_), do: []
end
