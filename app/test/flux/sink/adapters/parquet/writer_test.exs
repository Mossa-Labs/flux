defmodule Flux.Sink.Adapters.Parquet.WriterTest do
  use ExUnit.Case, async: true

  alias Explorer.DataFrame
  alias Flux.Sink.Adapters.Parquet.{Paths, Writer}

  setup do
    dir = Path.join(Paths.base_dir(), "writer-test-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp write(target, values, attempts \\ 1),
    do: Writer.write(target, %{"i" => :integer}, %{"i" => values}, :snappy, attempts)

  defp read(path), do: DataFrame.to_columns(DataFrame.from_parquet!(path))

  test "writes a file and leaves no temporary files behind", %{dir: dir} do
    path = Path.join(dir, "a/out.parquet")

    assert {:ok, ^path, bytes} = write(path, [1, 2])
    assert bytes == File.stat!(path).size
    assert File.ls!(Path.dirname(path)) == ["out.parquet"]
    assert read(path) == %{"i" => [1, 2]}
  end

  test "never replaces an existing file", %{dir: dir} do
    path = Path.join(dir, "taken.parquet")
    {:ok, _, _} = write(path, [1])

    assert {:error, :eexist} = write(path, [2])
    assert read(path) == %{"i" => [1]}
    assert File.ls!(dir) == ["taken.parquet"]
  end

  test "retries a taken name with a fresh one from the target function", %{dir: dir} do
    taken = Path.join(dir, "taken.parquet")
    free = Path.join(dir, "sub/free.parquet")
    {:ok, _, _} = write(taken, [1])
    names = start_supervised!({Agent, fn -> [taken, free] end})
    next = fn -> {:ok, Agent.get_and_update(names, fn [name | rest] -> {name, rest} end)} end

    assert {:ok, ^free, _} = write(next, [2], 3)
    assert read(taken) == %{"i" => [1]}
    assert read(free) == %{"i" => [2]}
    assert File.ls!(dir) |> Enum.sort() == ["sub", "taken.parquet"]
  end

  test "gives up after the last attempt and cleans up", %{dir: dir} do
    taken = Path.join(dir, "taken.parquet")
    {:ok, _, _} = write(taken, [1])

    assert {:error, :eexist} = write(fn -> {:ok, taken} end, [2], 3)
    assert File.ls!(dir) == ["taken.parquet"]
  end

  test "a final filename at the filesystem's name limit still writes", %{dir: dir} do
    # Fits as a filename, but not with a suffix derived from it.
    name = String.duplicate("a", name_max(dir) - 8) <> ".parquet"
    path = Path.join(dir, name)

    assert {:ok, ^path, _} = write(path, [1])
    assert File.ls!(dir) == [name]
  end

  test "a filename over the limit fails before anything is written", %{dir: dir} do
    path = Path.join(dir, String.duplicate("a", 256) <> ".parquet")

    assert {:error, :enametoolong} = write(path, [1])
    refute File.exists?(dir)
  end

  describe "publish/3 without hard links" do
    setup %{dir: dir} do
      File.mkdir_p!(dir)
      tmp = Path.join(dir, Paths.scratch_name(".tmp"))
      File.write!(tmp, "new")
      %{tmp: tmp, path: Path.join(dir, "out.parquet")}
    end

    test "renames into place when the name is free", %{tmp: tmp, path: path} do
      assert :ok = Writer.publish(tmp, path, fn _, _ -> {:error, :eperm} end)
      assert File.read!(path) == "new"
      refute File.exists?(tmp)
    end

    test "never replaces an existing file", %{tmp: tmp, path: path} do
      File.write!(path, "old")

      assert {:error, :eexist} = Writer.publish(tmp, path, fn _, _ -> {:error, :enotsup} end)
      assert File.read!(path) == "old"
    end

    test "only falls back when the filesystem can't hard-link", %{tmp: tmp, path: path} do
      for reason <- [:emlink, :enospc, :eacces, :enametoolong] do
        assert {:error, ^reason} = Writer.publish(tmp, path, fn _, _ -> {:error, reason} end)
        refute File.exists?(path)
      end
    end
  end

  test "uid/0 is a 128-bit id" do
    uids = for _ <- 1..1_000, do: Paths.uid()
    assert Enum.all?(uids, &(String.length(&1) == 26 and &1 =~ ~r/^[a-z2-7]+$/))
    assert length(Enum.uniq(uids)) == 1_000
  end

  # The longest file name `dir`'s filesystem accepts (255 on most, less on
  # e.g. eCryptfs), so the test doesn't assume a limit.
  defp name_max(dir) do
    File.mkdir_p!(dir)
    name_max(dir, 9, 255)
  end

  defp name_max(_dir, lo, hi) when lo >= hi, do: lo

  defp name_max(dir, lo, hi) do
    mid = div(lo + hi + 1, 2)
    probe = Path.join(dir, String.duplicate("n", mid))

    case File.touch(probe) do
      :ok ->
        File.rm!(probe)
        name_max(dir, mid, hi)

      {:error, _} ->
        name_max(dir, lo, mid - 1)
    end
  end
end
