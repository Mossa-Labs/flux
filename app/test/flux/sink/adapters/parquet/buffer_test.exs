defmodule Flux.Sink.Adapters.Parquet.BufferTest do
  use ExUnit.Case, async: true

  alias Explorer.DataFrame
  alias Flux.Sink.Adapters.Parquet.{Buffer, Paths}

  setup do
    directory = "buffer-test-#{System.unique_integer([:positive])}"
    root = Path.join(Paths.base_dir(), directory)
    on_exit(fn -> File.rm_rf!(root) end)
    %{directory: directory, root: root}
  end

  defp start_buffer(config, key \\ {"sink-#{System.unique_integer([:positive])}", "p1"}) do
    pid = start_supervised!({Buffer, key: key, config: config}, id: key)
    {pid, config}
  end

  defp files(root), do: root |> Path.join("**/*.parquet") |> Path.wildcard() |> Enum.sort()

  defp read_all(root), do: Enum.map(files(root), &DataFrame.from_parquet!/1)

  test "rotates files by row count", %{directory: directory, root: root} do
    {pid, config} = start_buffer(%{"directory" => directory, "max_rows" => 3})

    for i <- 1..7, do: assert(:ok = Buffer.append(pid, %{"i" => i}, config))

    assert length(files(root)) == 2
    :ok = Buffer.flush(pid)

    frames = read_all(root)
    assert Enum.map(frames, &DataFrame.n_rows/1) |> Enum.sort() == [1, 3, 3]

    assert frames |> Enum.flat_map(&DataFrame.to_columns(&1)["i"]) |> Enum.sort() ==
             Enum.to_list(1..7)
  end

  test "rotates files by age on tick", %{directory: directory, root: root} do
    {pid, config} = start_buffer(%{"directory" => directory, "max_interval_seconds" => 60})
    :ok = Buffer.append(pid, %{"i" => 1}, config)

    send(pid, :tick)
    _ = :sys.get_state(pid)
    assert files(root) == []

    :sys.replace_state(pid, fn state ->
      update_in(state.partitions, fn parts ->
        Map.new(parts, fn {k, part} -> {k, %{part | opened_at: part.opened_at - 61_000}} end)
      end)
    end)

    send(pid, :tick)
    _ = :sys.get_state(pid)
    assert [_file] = files(root)
  end

  test "flushes on shutdown", %{directory: directory, root: root} do
    key = {"sink-#{System.unique_integer([:positive])}", "p1"}
    {pid, config} = start_buffer(%{"directory" => directory}, key)
    :ok = Buffer.append(pid, %{"i" => 1}, config)
    assert files(root) == []

    ref = Process.monitor(pid)
    :ok = stop_supervised(key)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}

    assert [file] = files(root)
    assert DataFrame.from_parquet!(file) |> DataFrame.n_rows() == 1
  end

  test "exits normally once idle with nothing buffered", %{directory: directory} do
    {pid, _config} = start_buffer(%{"directory" => directory})
    ref = Process.monitor(pid)

    :sys.replace_state(pid, &%{&1 | last_activity: &1.last_activity - 3_600_000})
    send(pid, :tick)

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
  end

  describe "schema drift" do
    test "rotate mode starts a new file with the widened schema", %{
      directory: directory,
      root: root
    } do
      {pid, config} = start_buffer(%{"directory" => directory})

      :ok = Buffer.append(pid, %{"id" => 1}, config)
      :ok = Buffer.append(pid, %{"id" => 2, "name" => "b"}, config)
      :ok = Buffer.append(pid, %{"id" => 3}, config)
      :ok = Buffer.flush(pid)

      frames = read_all(root) |> Enum.sort_by(&length(DataFrame.names(&1)))
      assert [first, second] = frames
      assert DataFrame.names(first) == ["id"]
      assert DataFrame.to_columns(second) == %{"id" => [2, 3], "name" => ["b", nil]}
    end

    test "rotate mode widens conflicting types to strings", %{directory: directory, root: root} do
      {pid, config} = start_buffer(%{"directory" => directory})

      :ok = Buffer.append(pid, %{"id" => 1}, config)
      :ok = Buffer.append(pid, %{"id" => "two"}, config)
      :ok = Buffer.flush(pid)

      dtypes = read_all(root) |> Enum.map(&DataFrame.dtypes(&1)["id"]) |> Enum.sort()
      assert dtypes == [:string, {:s, 64}]
    end

    test "strict mode rejects mismatched records", %{directory: directory, root: root} do
      {pid, config} = start_buffer(%{"directory" => directory, "schema_mode" => "strict"})

      :ok = Buffer.append(pid, %{"id" => 1}, config)

      assert {:error, {:schema_mismatch, [_]}} =
               Buffer.append(pid, %{"id" => 2, "x" => 1}, config)

      assert {:error, {:schema_mismatch, [_]}} = Buffer.append(pid, %{"id" => "3"}, config)
      :ok = Buffer.append(pid, %{"id" => nil}, config)
      :ok = Buffer.flush(pid)

      assert [frame] = read_all(root)
      assert DataFrame.to_columns(frame) == %{"id" => [1, nil]}
    end

    test "explicit schemas project and coerce", %{directory: directory, root: root} do
      {pid, config} =
        start_buffer(%{
          "directory" => directory,
          "schema" => %{"id" => "integer", "at" => "timestamp"}
        })

      :ok =
        Buffer.append(pid, %{"id" => "7", "at" => "2026-10-19T00:00:00Z", "drop" => 1}, config)

      assert {:error, {:schema_mismatch, _}} = Buffer.append(pid, %{"id" => "x"}, config)
      :ok = Buffer.flush(pid)

      assert [frame] = read_all(root)

      assert DataFrame.dtypes(frame) == %{
               "id" => {:s, 64},
               "at" => {:naive_datetime, :microsecond}
             }

      assert DataFrame.to_columns(frame)["id"] == [7]
    end
  end

  test "writes one file per partition", %{directory: directory, root: root} do
    {pid, config} =
      start_buffer(%{"directory" => directory, "partition_template" => "region={region}/"})

    for region <- ["eu", "us", "eu"], do: :ok = Buffer.append(pid, %{"region" => region}, config)
    :ok = Buffer.flush(pid)

    dirs = files(root) |> Enum.map(&(&1 |> Path.dirname() |> Path.basename()))
    assert Enum.sort(dirs) == ["region=eu", "region=us"]
  end

  test "a config change flushes under the old settings first", %{directory: directory, root: root} do
    {pid, config} = start_buffer(%{"directory" => directory})
    :ok = Buffer.append(pid, %{"i" => 1}, config)

    new_config = Map.put(config, "compression", "zstd")
    :ok = Buffer.append(pid, %{"i" => 2}, new_config)

    assert [_flushed] = files(root)
    assert :sys.get_state(pid).settings.compression == :zstd
  end

  test "emits flush telemetry", %{directory: directory} do
    handler = "parquet-flush-#{System.unique_integer()}"
    test_pid = self()

    :telemetry.attach(
      handler,
      [:flux, :sink, :parquet, :flush],
      fn _event, measurements, metadata, _ ->
        send(test_pid, {:flush, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    {sink, _} = key = {"sink-#{System.unique_integer([:positive])}", "p1"}
    {pid, config} = start_buffer(%{"directory" => directory}, key)
    :ok = Buffer.append(pid, %{"i" => 1}, config)
    :ok = Buffer.flush(pid)

    assert_receive {:flush, %{rows: 1, bytes: bytes},
                    %{status: :ok, sink: ^sink, pipeline_id: "p1"}}

    assert bytes > 0
  end
end
