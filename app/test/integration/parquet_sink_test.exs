defmodule Flux.Integration.ParquetSinkTest do
  @moduledoc """
  End-to-end Parquet sink round-trips through the real Explorer writer/reader.

  Run with: `mix test --include integration test/integration/parquet_sink_test.exs`
  """

  use ExUnit.Case, async: false

  @moduletag :integration

  alias Explorer.DataFrame
  alias Flux.Sink.Adapters.Parquet
  alias Flux.Sink.Adapters.Parquet.{Buffer, Paths}
  alias Flux.Sink.Adapters.Parquet.Supervisor, as: Buffers

  @rows 100_000

  setup do
    directory = "integration-#{System.unique_integer([:positive])}"
    root = Path.join(Paths.base_dir(), directory)
    on_exit(fn -> File.rm_rf!(root) end)
    %{directory: directory, root: root}
  end

  defp deliver_all(records, config, key) do
    {sink_id, pipeline_id} = key
    on_exit(fn -> Buffers.stop_buffer(key) end)

    for record <- records,
        do: :ok = Parquet.deliver(record, config, sink_id: sink_id, pipeline_id: pipeline_id)

    {:ok, pid} = Buffers.buffer(key, config)
    :ok = Buffer.flush(pid)
  end

  defp files(root), do: root |> Path.join("**/*.parquet") |> Path.wildcard() |> Enum.sort()

  defp read_all(root) do
    root |> files() |> Enum.map(&DataFrame.from_parquet!/1) |> DataFrame.concat_rows()
  end

  # 10 columns of mixed types, deterministic per index.
  defp record(i) do
    %{
      "id" => i,
      "name" => "user-#{i}",
      "score" => i / 7,
      "active" => rem(i, 2) == 0,
      "bucket" => rem(i, 13),
      "country" => Enum.at(~w(US DE JP BR), rem(i, 4)),
      "maybe" => if(rem(i, 5) == 0, do: nil, else: "v#{i}"),
      "tags" => ["t#{rem(i, 3)}"],
      "meta" => %{"source" => "it", "n" => i},
      "amount" => i * 100
    }
  end

  for codec <- ~w(snappy gzip zstd) do
    @tag timeout: 300_000
    test "round-trips #{@rows} rows × 10 columns with #{codec}", %{
      directory: directory,
      root: root
    } do
      config = %{"type" => "parquet", "directory" => directory, "compression" => unquote(codec)}
      key = {"it-#{unquote(codec)}", "p"}

      deliver_all(Stream.map(1..@rows, &record/1), config, key)

      assert [_single_file] = files(root)
      df = read_all(root)
      assert DataFrame.n_rows(df) == @rows
      assert length(DataFrame.names(df)) == 10

      assert DataFrame.dtypes(df) == %{
               "id" => {:s, 64},
               "name" => :string,
               "score" => {:f, 64},
               "active" => :boolean,
               "bucket" => {:s, 64},
               "country" => :string,
               "maybe" => :string,
               "tags" => :string,
               "meta" => :string,
               "amount" => {:s, 64}
             }

      sample = df |> DataFrame.slice(41_999, 1) |> DataFrame.to_rows() |> hd()
      expected = record(42_000)

      assert sample["id"] == expected["id"]
      assert sample["score"] == expected["score"]
      assert sample["country"] == expected["country"]
      assert sample["maybe"] == nil
      assert Jason.decode!(sample["meta"]) == expected["meta"]
      assert Jason.decode!(sample["tags"]) == expected["tags"]
    end
  end

  test "rotates by row count", %{directory: directory, root: root} do
    config = %{"type" => "parquet", "directory" => directory, "max_rows" => 1_000}
    deliver_all(Enum.map(1..2_500, &record/1), config, {"it-rows", "p"})

    sizes = root |> files() |> Enum.map(&(&1 |> DataFrame.from_parquet!() |> DataFrame.n_rows()))
    assert Enum.sort(sizes) == [500, 1_000, 1_000]
  end

  test "rotates by time threshold", %{directory: directory, root: root} do
    config = %{"type" => "parquet", "directory" => directory, "max_interval_seconds" => 1}
    key = {"it-time", "p"}
    on_exit(fn -> Buffers.stop_buffer(key) end)

    test_pid = self()
    handler = "it-time-flush"

    :telemetry.attach(
      handler,
      [:flux, :sink, :parquet, :flush],
      fn
        _event, measurements, %{sink: "it-time"}, _ -> send(test_pid, {:flushed, measurements})
        _event, _measurements, _metadata, _ -> :ok
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    :ok = Parquet.deliver(record(1), config, sink_id: "it-time", pipeline_id: "p")

    # No explicit flush: the buffer's own timer must rotate the file.
    assert_receive {:flushed, %{rows: 1}}, 5_000
    assert DataFrame.n_rows(read_all(root)) == 1
  end

  test "handles schema mismatch on a later batch", %{directory: directory, root: root} do
    rotate = %{"type" => "parquet", "directory" => Path.join(directory, "rotate")}
    deliver_all([%{"a" => 1}, %{"a" => 2, "b" => "new"}], rotate, {"it-rotate", "p"})
    assert length(files(Path.join(root, "rotate"))) == 2

    strict = %{
      "type" => "parquet",
      "directory" => Path.join(directory, "strict"),
      "schema_mode" => "strict"
    }

    key = {"it-strict", "p"}
    on_exit(fn -> Buffers.stop_buffer(key) end)

    assert :ok = Parquet.deliver(%{"a" => 1}, strict, sink_id: "it-strict", pipeline_id: "p")

    assert {:error, {:schema_mismatch, _}} =
             Parquet.deliver(%{"a" => "x"}, strict, sink_id: "it-strict", pipeline_id: "p")
  end

  test "partitioned writes produce hive-style folders", %{directory: directory, root: root} do
    config = %{
      "type" => "parquet",
      "directory" => directory,
      "partition_template" => "year={yyyy}/country={country}/"
    }

    deliver_all(Enum.map(1..40, &record/1), config, {"it-part", "p"})

    year = Integer.to_string(DateTime.utc_now().year)

    dirs =
      root
      |> files()
      |> Enum.map(&(&1 |> Path.dirname() |> Path.relative_to(root)))
      |> Enum.sort()

    assert dirs == Enum.map(~w(BR DE JP US), &"p/year=#{year}/country=#{&1}")
    assert DataFrame.n_rows(read_all(root)) == 40
  end

  test "explicit schema is honoured", %{directory: directory, root: root} do
    config = %{
      "type" => "parquet",
      "directory" => directory,
      "schema" => %{"id" => "integer", "amount" => "float", "seen" => "date"}
    }

    deliver_all(
      [%{"id" => "1", "amount" => 3, "seen" => "2026-10-19", "extra" => true}],
      config,
      {"it-explicit", "p"}
    )

    df = read_all(root)
    assert DataFrame.dtypes(df) == %{"id" => {:s, 64}, "amount" => {:f, 64}, "seen" => :date}
    assert DataFrame.to_rows(df) == [%{"id" => 1, "amount" => 3.0, "seen" => ~D[2026-10-19]}]
  end
end
