defmodule Flux.Sink.Adapters.ParquetTest do
  use ExUnit.Case, async: true

  alias Explorer.DataFrame
  alias Flux.Sink.Adapters.Parquet
  alias Flux.Sink.Adapters.Parquet.Paths
  alias Flux.Sink.Adapters.Parquet.Supervisor, as: Buffers

  use Flux.SinkConformance,
    adapter: Parquet,
    type: "parquet",
    valid_config: %{"directory" => "conformance"},
    invalid_configs: [
      %{},
      %{"directory" => "../escape"},
      %{"directory" => "ok", "compression" => "lzma"},
      %{"directory" => "ok", "path_template" => "fixed-name.parquet"}
    ],
    deliver_config: %{"directory" => "conformance"},
    test_connection_config: %{"directory" => "conformance"}

  setup do
    directory = "adapter-test-#{System.unique_integer([:positive])}"
    root = Path.join(Paths.base_dir(), directory)
    on_exit(fn -> File.rm_rf!(root) end)
    %{directory: directory, root: root}
  end

  describe "validate_config/1" do
    test "a minimal config is valid" do
      assert :ok = Parquet.validate_config(%{"directory" => "events"})
    end

    test "a full config is valid" do
      assert :ok =
               Parquet.validate_config(%{
                 "directory" => "events",
                 "path_template" => "{pipeline_id}/{partition}{date}-{uid}.parquet",
                 "partition_template" => "year={yyyy}/region={region}/",
                 "compression" => "zstd",
                 "compression_level" => 9,
                 "max_rows" => 5_000,
                 "max_interval_seconds" => 30,
                 "schema" => %{"id" => "integer", "at" => "timestamp"},
                 "schema_mode" => "strict"
               })
    end

    test "requires a safe directory" do
      assert {:error, ["directory is required"]} = Parquet.validate_config(%{})
      assert {:error, [msg]} = Parquet.validate_config(%{"directory" => "/var/data"})
      assert msg =~ "relative"
    end

    test "checks path_template" do
      base = %{"directory" => "d"}

      assert {:error, [msg]} =
               Parquet.validate_config(Map.put(base, "path_template", "x-{uid}.csv"))

      assert msg =~ ".parquet"

      assert {:error, [msg]} =
               Parquet.validate_config(Map.put(base, "path_template", "x-{seq}.parquet"))

      assert msg =~ "{uid} or {timestamp}"

      assert {:error, [msg]} =
               Parquet.validate_config(
                 Map.merge(base, %{
                   "path_template" => "{uid}.parquet",
                   "partition_template" => "r={region}"
                 })
               )

      assert msg =~ "{partition}"
    end

    test "checks compression and levels" do
      base = %{"directory" => "d"}

      for codec <- ~w(snappy gzip zstd none),
          do: assert(:ok = Parquet.validate_config(Map.put(base, "compression", codec)))

      assert {:error, [_]} = Parquet.validate_config(Map.put(base, "compression", "brotli"))

      assert {:error, [msg]} =
               Parquet.validate_config(
                 Map.merge(base, %{"compression" => "gzip", "compression_level" => 12})
               )

      assert msg =~ "between 1 and 9"

      assert {:error, [msg]} = Parquet.validate_config(Map.put(base, "compression_level", 3))
      assert msg =~ "only supported"
    end

    test "checks thresholds, schema and schema_mode" do
      base = %{"directory" => "d"}
      assert {:error, [_]} = Parquet.validate_config(Map.put(base, "max_rows", 0))
      assert {:error, [_]} = Parquet.validate_config(Map.put(base, "max_interval_seconds", -1))
      assert {:error, [msg]} = Parquet.validate_config(Map.put(base, "schema", %{"a" => "uuid"}))
      assert msg =~ "unknown type"
      assert {:error, [_]} = Parquet.validate_config(Map.put(base, "schema_mode", "evolve"))
    end
  end

  describe "deliver/3" do
    test "buffers per sink and pipeline, then writes on flush", %{
      directory: directory,
      root: root
    } do
      config = %{"type" => "parquet", "directory" => directory}
      sink_id = System.unique_integer([:positive])
      opts = [sink_id: sink_id, pipeline_id: 42]

      assert :ok = Parquet.deliver(%{"id" => 1, "meta" => %{"k" => "v"}}, config, opts)
      assert :ok = Parquet.deliver(%{id: 2}, config, opts)

      {:ok, pid} = Buffers.buffer({sink_id, 42}, config)
      :ok = Flux.Sink.Adapters.Parquet.Buffer.flush(pid)
      on_exit(fn -> Buffers.stop_buffer({sink_id, 42}) end)

      assert [file] = root |> Path.join("42/*.parquet") |> Path.wildcard()

      assert DataFrame.to_columns(DataFrame.from_parquet!(file)) == %{
               "id" => [1, 2],
               "meta" => [~s({"k":"v"}), nil]
             }
    end

    test "rejects non-map data" do
      assert {:error, :invalid_data} = Parquet.deliver("nope", %{"directory" => "d"}, [])
    end

    test "returns schema mismatches in strict mode", %{directory: directory} do
      config = %{"type" => "parquet", "directory" => directory, "schema_mode" => "strict"}
      opts = [sink_id: System.unique_integer([:positive]), pipeline_id: 1]
      on_exit(fn -> Buffers.stop_buffer({opts[:sink_id], 1}) end)

      assert :ok = Parquet.deliver(%{"a" => 1}, config, opts)
      assert {:error, {:schema_mismatch, _}} = Parquet.deliver(%{"a" => "x"}, config, opts)
    end
  end

  describe "test_connection/1" do
    test "creates the directory and verifies it is writable", %{directory: directory, root: root} do
      assert :ok = Parquet.test_connection(%{"directory" => directory})
      assert File.dir?(root)
      assert File.ls!(root) == []
    end

    test "refuses directories outside the base dir" do
      assert {:error, _} = Parquet.test_connection(%{"directory" => "../outside"})
    end
  end
end
