defmodule Flux.Sink.Adapters.Parquet do
  @moduledoc """
  Parquet file sink adapter (Community).

  Buffers pipeline records and writes them as columnar Parquet files on the
  local filesystem, under the operator-configured base directory
  (`FLUX_PARQUET_BASE_DIR`). To land files in object storage, point the base
  directory at a mounted bucket (see `docs/connectors/parquet.md`).

  Delivery is buffered: `deliver/3` hands the record to a per-`{sink, pipeline}`
  `Flux.Sink.Adapters.Parquet.Buffer` and returns as soon as it is held. Files
  rotate by row count, by age, on schema change and on shutdown.

  ## Configuration

      %{
        "type" => "parquet",
        "directory" => "events",                      # Required, relative to the base dir
        "path_template" => "{pipeline_id}/{partition}part-{timestamp}-{seq}-{uid}.parquet",
        "partition_template" => "year={yyyy}/month={MM}/",   # Optional, default: ""
        "compression" => "snappy",                    # snappy | gzip | zstd | none
        "compression_level" => 3,                     # Optional, gzip 1..9, zstd -7..22
        "max_rows" => 100_000,                        # Rotate after N rows
        "max_interval_seconds" => 600,                # Rotate after N seconds
        "schema" => %{"id" => "integer"},             # Optional explicit schema
        "schema_mode" => "rotate"                     # rotate | strict (inferred schemas only)
      }

  Placeholders are documented in `Flux.Sink.Adapters.Parquet.Paths`; types and
  coercion rules in `Flux.Sink.Adapters.Parquet.Schema`.
  """

  @behaviour Flux.Sink.Adapter

  alias Flux.Sink.Adapters.Parquet.{Buffer, Paths, Schema, Settings, Writer}
  alias Flux.Sink.Adapters.Parquet.Supervisor, as: Buffers

  @max_rows_limit 10_000_000
  @schema_modes ~w(rotate strict)

  @impl Flux.Sink.Adapter
  def deliver(data, config, opts) when is_map(data) do
    key = {Keyword.get(opts, :sink_id) || {:config, :erlang.phash2(config)}, opts[:pipeline_id]}
    append(key, stringify_keys(data), config, 1)
  end

  def deliver(_data, _config, _opts), do: {:error, :invalid_data}

  # A buffer exits :normal once idle, so a lookup can race its exit — retry once
  # against a freshly started buffer.
  defp append(key, row, config, retries) do
    with {:ok, pid} <- Buffers.buffer(key, config) do
      Buffer.append(pid, row, config)
    end
  catch
    :exit, {reason, _} when retries > 0 and reason in [:noproc, :normal] ->
      append(key, row, config, retries - 1)

    :exit, {:timeout, _} ->
      {:error, :buffer_timeout}

    :exit, {reason, _} ->
      {:error, {:buffer_unavailable, reason}}
  end

  @doc "Flushes every running Parquet buffer now (operator / test helper)."
  @spec flush_all() :: :ok
  def flush_all, do: Enum.each(Buffers.buffers(), &Buffer.flush/1)

  @impl Flux.Sink.Adapter
  def validate_config(config) do
    Flux.Sink.Validation.run(config, [
      &validate_directory/1,
      &validate_path_template/1,
      &validate_partition_template/1,
      &validate_compression/1,
      &validate_compression_level/1,
      &validate_max_rows/1,
      &validate_interval/1,
      &validate_schema/1,
      &validate_schema_mode/1
    ])
  end

  defp validate_directory(config), do: Paths.validate_directory(Map.get(config, "directory"))

  defp validate_path_template(config) do
    case Map.get(config, "path_template") do
      nil ->
        :ok

      template when is_binary(template) ->
        with :ok <- Paths.validate_template(template, :path) do
          cond do
            not String.ends_with?(template, ".parquet") ->
              {:error, "path_template must end in .parquet"}

            not (Paths.uses?(template, "uid") or Paths.uses?(template, "timestamp")) ->
              {:error,
               "path_template must include {uid} or {timestamp} so files never overwrite each other"}

            present?(config["partition_template"]) and not Paths.uses?(template, "partition") ->
              {:error, "path_template must include {partition} when partition_template is set"}

            true ->
              Paths.validate_file_name(template, partition_template(config))
          end
        end

      _ ->
        {:error, "path_template must be a string"}
    end
  end

  defp partition_template(config) do
    case config["partition_template"] do
      template when is_binary(template) -> template
      _ -> ""
    end
  end

  defp validate_partition_template(config) do
    case Map.get(config, "partition_template") do
      nil -> :ok
      template when is_binary(template) -> Paths.validate_template(template, :partition)
      _ -> {:error, "partition_template must be a string"}
    end
  end

  defp validate_compression(config) do
    case Map.get(config, "compression") do
      nil ->
        :ok

      codec ->
        if codec in Writer.compressions(),
          do: :ok,
          else: {:error, "compression must be one of: #{Enum.join(Writer.compressions(), ", ")}"}
    end
  end

  defp validate_compression_level(config) do
    codec = Map.get(config, "compression") || Settings.default_compression()

    case {Map.get(config, "compression_level"), Writer.level_range(codec)} do
      {nil, _} ->
        :ok

      {_level, nil} ->
        {:error, "compression_level is only supported for gzip and zstd"}

      {level, first..last//_} when is_integer(level) and level >= first and level <= last ->
        :ok

      {_level, first..last//_} ->
        {:error, "compression_level for #{codec} must be between #{first} and #{last}"}
    end
  end

  defp validate_max_rows(config) do
    case Map.get(config, "max_rows") do
      nil -> :ok
      rows when is_integer(rows) and rows > 0 and rows <= @max_rows_limit -> :ok
      _ -> {:error, "max_rows must be an integer between 1 and #{@max_rows_limit}"}
    end
  end

  defp validate_interval(config) do
    case Map.get(config, "max_interval_seconds") do
      nil -> :ok
      seconds when is_integer(seconds) and seconds > 0 -> :ok
      _ -> {:error, "max_interval_seconds must be a positive integer"}
    end
  end

  defp validate_schema(config) do
    case Map.get(config, "schema") do
      schema when schema in [nil, %{}] -> :ok
      schema -> with {:ok, _} <- Schema.parse_explicit(schema), do: :ok
    end
  end

  defp validate_schema_mode(config) do
    case Map.get(config, "schema_mode") do
      nil -> :ok
      mode when mode in @schema_modes -> :ok
      _ -> {:error, "schema_mode must be one of: #{Enum.join(@schema_modes, ", ")}"}
    end
  end

  @impl Flux.Sink.Adapter
  def test_connection(config) do
    probe = Paths.scratch_name(".probe")

    with :ok <- Paths.validate_directory(Map.get(config, "directory")),
         {:ok, root} <- Paths.root(config),
         :ok <- File.mkdir_p(root),
         path = Path.join(root, probe),
         :ok <- File.write(path, "") do
      File.rm(path)
    else
      {:error, :path_escape} -> {:error, :path_escape}
      {:error, reason} when is_atom(reason) -> {:error, {:not_writable, reason}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp stringify_keys(data), do: Map.new(data, fn {key, value} -> {to_string(key), value} end)

  defp present?(value), do: value not in [nil, ""]
end
