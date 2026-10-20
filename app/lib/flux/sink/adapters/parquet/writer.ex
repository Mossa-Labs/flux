defmodule Flux.Sink.Adapters.Parquet.Writer do
  @moduledoc """
  Turns a buffered, column-oriented batch into a Parquet file on disk.

  Files are written to a hidden temporary sibling and then renamed into place,
  so a reader listing the directory never sees a partially written file.
  """

  alias Explorer.DataFrame
  alias Flux.Sink.Adapters.Parquet.Schema

  @compressions ~w(snappy gzip zstd none)

  @doc "The compression codec names accepted in sink config."
  @spec compressions() :: [String.t()]
  def compressions, do: @compressions

  @doc """
  Writes `columns` (`%{name => values}`, values in row order) with `schema` to
  `path`. Returns the number of bytes written.
  """
  @spec write(String.t(), Schema.t(), %{String.t() => list()}, term()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def write(path, schema, columns, compression) do
    tmp = Path.join(Path.dirname(path), ".#{Path.basename(path)}.tmp")

    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, df} <- build(schema, columns),
         :ok <- DataFrame.to_parquet(df, tmp, compression: compression),
         :ok <- File.rename(tmp, path),
         {:ok, %File.Stat{size: size}} <- File.stat(path) do
      {:ok, size}
    else
      {:error, reason} ->
        _ = File.rm(tmp)
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
