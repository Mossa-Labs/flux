defmodule Flux.Sink.Adapters.Parquet.SweeperTest do
  use ExUnit.Case, async: true

  alias Flux.Sink.Adapters.Parquet.{Paths, Sweeper}

  setup do
    root = Path.join(Paths.base_dir(), "sweeper-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "year=2026"))
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  defp touch(path, age_seconds) do
    File.write!(path, "x")
    File.touch!(path, System.os_time(:second) - age_seconds)
    path
  end

  test "removes stale temporary files anywhere under the root", %{root: root} do
    stale = touch(Path.join(root, "year=2026/" <> Paths.scratch_name(".tmp")), 7_200)
    stale_top = touch(Path.join(root, Paths.scratch_name(".tmp")), 7_200)
    fresh = touch(Path.join(root, Paths.scratch_name(".tmp")), 10)
    data = touch(Path.join(root, "year=2026/part-1.parquet"), 7_200)
    probe = touch(Path.join(root, Paths.scratch_name(".probe")), 7_200)

    assert Sweeper.sweep_root(root, :timer.hours(1)) == 2
    refute File.exists?(stale)
    refute File.exists?(stale_top)
    assert File.exists?(fresh)
    assert File.exists?(data)
    assert File.exists?(probe)
  end

  test "a missing root sweeps nothing" do
    assert Sweeper.sweep_root(Path.join(Paths.base_dir(), "does-not-exist")) == 0
  end
end
