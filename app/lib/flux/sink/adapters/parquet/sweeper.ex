defmodule Flux.Sink.Adapters.Parquet.Sweeper do
  @moduledoc """
  Removes temporary files left behind by interrupted Parquet writes.

  A write that dies mid-encode (or between publishing a file and deleting its
  temporary name) leaves a hidden `.flux-<uid>.tmp` file in the target
  directory. Buffers ask for their sink's root to be swept when they start;
  each root is swept at most once per node, in this process, so neither the
  buffer nor delivery waits on a directory walk.

  Only files older than the grace period (default one hour, configurable with
  `config :flux, Flux.Sink.Adapters.Parquet, temp_file_grace_ms:`) are removed,
  so a write still in progress — on this node or another sharing the mount —
  is never touched.
  """

  use GenServer

  require Logger

  alias Flux.Sink.Adapters.Parquet.Paths

  @default_grace_ms :timer.hours(1)

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Asks for the sink root of `directory` to be swept (once per node)."
  @spec sweep(String.t() | nil) :: :ok
  def sweep(directory) when is_binary(directory),
    do: GenServer.cast(__MODULE__, {:sweep, directory})

  def sweep(_directory), do: :ok

  @doc "Removes stale temporary files under `root` now. Returns how many."
  @spec sweep_root(String.t(), non_neg_integer()) :: non_neg_integer()
  def sweep_root(root, grace_ms \\ grace_ms()) do
    cutoff = System.os_time(:second) - div(grace_ms, 1_000)

    root
    |> Path.join("**/" <> Paths.scratch_glob(".tmp"))
    |> Path.wildcard(match_dot: true)
    |> Enum.count(fn path ->
      match?(
        {:ok, %File.Stat{type: :regular, mtime: mtime}} when mtime < cutoff,
        File.stat(path, time: :posix)
      ) and File.rm(path) == :ok
    end)
  end

  @impl true
  def init(_opts), do: {:ok, MapSet.new()}

  @impl true
  def handle_cast({:sweep, directory}, swept) do
    with {:ok, root} <- Paths.root(%{"directory" => directory}),
         false <- MapSet.member?(swept, root) do
      case sweep_root(root) do
        0 -> :ok
        count -> Logger.info("Parquet sink removed #{count} stale temporary files under #{root}")
      end

      {:noreply, MapSet.put(swept, root)}
    else
      _ -> {:noreply, swept}
    end
  end

  defp grace_ms do
    :flux
    |> Application.get_env(Flux.Sink.Adapters.Parquet, [])
    |> Keyword.get(:temp_file_grace_ms, @default_grace_ms)
  end
end
