defmodule Flux.Sink.Adapters.Parquet.WriterTest do
  use ExUnit.Case, async: true

  alias Explorer.DataFrame
  alias Flux.Sink.Adapters.Parquet.{Paths, Writer}

  setup do
    dir = Path.join(Paths.base_dir(), "writer-test-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "writes a file and leaves no temporary files behind", %{dir: dir} do
    path = Path.join(dir, "a/out.parquet")

    assert {:ok, bytes} = Writer.write(path, %{"i" => :integer}, %{"i" => [1, 2]}, :snappy)
    assert bytes > 0
    assert File.ls!(Path.dirname(path)) == ["out.parquet"]
    assert DataFrame.to_columns(DataFrame.from_parquet!(path)) == %{"i" => [1, 2]}
  end

  test "never replaces an existing file", %{dir: dir} do
    path = Path.join(dir, "taken.parquet")
    {:ok, _} = Writer.write(path, %{"i" => :integer}, %{"i" => [1]}, :snappy)

    assert {:error, :eexist} = Writer.write(path, %{"i" => :integer}, %{"i" => [2]}, :snappy)
    assert DataFrame.to_columns(DataFrame.from_parquet!(path)) == %{"i" => [1]}
    assert File.ls!(dir) == ["taken.parquet"]
  end

  test "a final filename near the 255-byte limit still writes", %{dir: dir} do
    # 250 bytes: fits as a filename, but not with a suffix derived from it.
    name = String.duplicate("a", 242) <> ".parquet"
    path = Path.join(dir, name)

    assert {:ok, _} = Writer.write(path, %{"i" => :integer}, %{"i" => [1]}, :snappy)
    assert File.ls!(dir) == [name]
  end

  test "uid/0 is a 128-bit id" do
    uids = for _ <- 1..1_000, do: Paths.uid()
    assert Enum.all?(uids, &(String.length(&1) == 26 and &1 =~ ~r/^[a-z2-7]+$/))
    assert length(Enum.uniq(uids)) == 1_000
  end
end
