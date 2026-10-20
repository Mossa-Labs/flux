defmodule Flux.Sink.Adapters.Parquet.Settings do
  @moduledoc """
  A Parquet sink config map, parsed once into a struct with defaults applied.

  Sink configs are validated on save (`Flux.Sink.Adapters.Parquet.validate_config/1`),
  so this module assumes a valid config and only fills in defaults.
  """

  alias Flux.Sink.Adapters.Parquet.{Schema, Writer}

  @default_path_template "{pipeline_id}/{partition}part-{timestamp}-{seq}-{uid}.parquet"
  @default_compression "snappy"
  @default_max_rows 100_000
  @default_max_interval_seconds 600

  defstruct [
    :directory,
    :compression,
    :schema,
    path_template: @default_path_template,
    partition_template: "",
    max_rows: @default_max_rows,
    interval_ms: @default_max_interval_seconds * 1_000,
    strict?: false
  ]

  @type t :: %__MODULE__{
          directory: String.t(),
          compression: term(),
          schema: Schema.t() | nil,
          path_template: String.t(),
          partition_template: String.t(),
          max_rows: pos_integer(),
          interval_ms: pos_integer(),
          strict?: boolean()
        }

  def default_path_template, do: @default_path_template
  def default_compression, do: @default_compression
  def default_max_rows, do: @default_max_rows
  def default_max_interval_seconds, do: @default_max_interval_seconds

  @spec from_config(map()) :: t()
  def from_config(config) do
    %__MODULE__{
      directory: Map.get(config, "directory"),
      path_template: present(config["path_template"]) || @default_path_template,
      partition_template: config["partition_template"] || "",
      compression:
        Writer.compression_opt(
          present(config["compression"]) || @default_compression,
          config["compression_level"]
        ),
      max_rows: config["max_rows"] || @default_max_rows,
      interval_ms: (config["max_interval_seconds"] || @default_max_interval_seconds) * 1_000,
      schema: explicit_schema(config["schema"]),
      strict?: config["schema_mode"] == "strict"
    }
  end

  defp explicit_schema(schema) when is_map(schema) and map_size(schema) > 0 do
    case Schema.parse_explicit(schema) do
      {:ok, schema} -> schema
      {:error, _} -> nil
    end
  end

  defp explicit_schema(_schema), do: nil

  defp present(value) when value in [nil, ""], do: nil
  defp present(value), do: value
end
