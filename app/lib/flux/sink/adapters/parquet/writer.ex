defmodule Flux.Sink.Adapters.Parquet.Writer do
  @moduledoc """
  Turns a buffered, column-oriented batch into a Parquet file on disk.

  Files are written to a hidden temporary sibling and then moved into place,
  so a reader listing the directory never sees a partially written file. An
  existing file is never replaced: if the target name is taken the write fails
  with `{:error, :eexist}` and the caller picks a new name.
  """

  alias Explorer.DataFrame
  alias Flux.Sink.Adapters.Parquet.{Paths, Schema}

  @compressions ~w(snappy gzip zstd none)

  @doc "The compression codec names accepted in sink config."
  @spec compressions() :: [String.t()]
  def compressions, do: @compressions

  @doc """
  Writes `columns` (`%{name => values}`, values in row order) with `schema` to
  a new file and returns its path and size in bytes.

  `target` is the destination path, or a function returning `{:ok, path}` that
  is called again for a fresh name each time the previous one is taken, up to
  `attempts` names in total. The file is encoded once; only the final move is
  retried.
  """
  @spec write(target, Schema.t(), %{String.t() => list()}, term(), pos_integer()) ::
          {:ok, String.t(), non_neg_integer()} | {:error, term()}
        when target: String.t() | (-> {:ok, String.t()} | {:error, term()})
  def write(target, schema, columns, compression, attempts \\ 1) do
    with {:ok, path} <- next_path(target),
         # A short temporary name in the same directory (so the final move stays
         # on one filesystem), independent of the final name: deriving it from
         # the final name would push long-but-valid filenames past the limit.
         tmp = Path.join(Path.dirname(path), Paths.scratch_name(".tmp")),
         {:ok, size} <- encode(tmp, schema, columns, compression) do
      case publish_new(tmp, path, target, attempts) do
        {:ok, path} ->
          {:ok, path, size}

        {:error, reason} ->
          _ = File.rm(tmp)
          {:error, reason}
      end
    end
  end

  defp next_path(target) do
    with {:ok, path} <- if(is_function(target, 0), do: target.(), else: {:ok, target}) do
      # Fail before encoding anything: the file could never be created.
      if Paths.names_fit?(path), do: {:ok, path}, else: {:error, :enametoolong}
    end
  end

  # The size is read from the temporary file, before the move: once the file
  # is published, a failure to stat it must not report its rows as lost.
  defp encode(tmp, schema, columns, compression) do
    with :ok <- File.mkdir_p(Path.dirname(tmp)),
         {:ok, df} <- build(schema, columns),
         :ok <- DataFrame.to_parquet(df, tmp, compression: compression),
         {:ok, %File.Stat{size: size}} <- File.stat(tmp) do
      {:ok, size}
    else
      {:error, reason} ->
        _ = File.rm(tmp)
        {:error, reason}
    end
  end

  # A fresh name may land in another directory (e.g. a `{uid}` directory);
  # linking or renaming across directories works within one filesystem.
  defp publish_new(tmp, path, target, attempts) do
    case publish(tmp, path) do
      {:error, :eexist} when attempts > 1 ->
        with {:ok, path} <- next_path(target),
             :ok <- File.mkdir_p(Path.dirname(path)) do
          publish_new(tmp, path, target, attempts - 1)
        end

      :ok ->
        {:ok, path}

      error ->
        error
    end
  end

  # Errors from `link(2)` that mean the filesystem cannot hard-link at all, as
  # opposed to this particular link failing (`:emlink`, `:enospc`, `:eacces`…),
  # which must not fall back to the non-atomic path.
  @no_hard_links [:enotsup, :eopnotsupp, :eperm, :enosys, :exdev]

  @doc false
  # Moves `tmp` to `path` without ever replacing an existing file. A hard link
  # is an atomic create-if-absent; filesystems without hard links (most FUSE
  # bucket mounts) fall back to check-then-rename, which is safe here because
  # names are unique per file and each buffer writes its files one at a time.
  # `link` is injectable so tests can exercise the fallback on any filesystem.
  @spec publish(String.t(), String.t(), (String.t(), String.t() -> :ok | {:error, atom()})) ::
          :ok | {:error, term()}
  def publish(tmp, path, link \\ &File.ln/2) do
    case link.(tmp, path) do
      :ok ->
        _ = File.rm(tmp)
        :ok

      {:error, reason} when reason in @no_hard_links ->
        if File.exists?(path), do: {:error, :eexist}, else: File.rename(tmp, path)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build(schema, columns) do
    dtypes = Schema.dtypes(schema)
    data = Enum.map(dtypes, fn {name, _dtype} -> {name, Map.fetch!(columns, name)} end)
    {:ok, DataFrame.new(data, dtypes: dtypes)}
  rescue
    error -> {:error, {:dataframe, Exception.message(error)}}
  end

  @doc """
  Maps a config codec name and optional level to Explorer's `:compression`
  option.
  """
  @spec compression_opt(String.t() | nil, integer() | nil) :: term()
  def compression_opt(name, level \\ nil)
  def compression_opt("none", _level), do: nil
  def compression_opt("snappy", _level), do: :snappy
  def compression_opt("gzip", nil), do: :gzip
  def compression_opt("gzip", level), do: {:gzip, level}
  def compression_opt("zstd", nil), do: :zstd
  def compression_opt("zstd", level), do: {:zstd, level}
  def compression_opt(nil, _level), do: :snappy

  @doc "Valid level range for a codec, or `nil` when it takes no level."
  @spec level_range(String.t()) :: Range.t() | nil
  def level_range("gzip"), do: 1..9
  def level_range("zstd"), do: -7..22
  def level_range(_name), do: nil
end
