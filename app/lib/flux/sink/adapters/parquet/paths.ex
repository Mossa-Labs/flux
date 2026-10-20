defmodule Flux.Sink.Adapters.Parquet.Paths do
  @moduledoc """
  Filesystem layout for the Parquet sink: the operator-controlled base
  directory, path/partition template rendering, and path-escape protection.

  Every file the sink writes lives under the base directory, which is set by
  the operator (`FLUX_PARQUET_BASE_DIR`), never by sink config. A sink's
  `directory` and templates are relative to it, and every rendered path is
  re-checked against it before anything touches the disk, so a sink can never
  write outside the base directory — not through `..`, an absolute path, or a
  record value interpolated into a partition.

  ## Placeholders

  `path_template` (one value per written file):
  `{pipeline_id}`, `{partition}`, `{timestamp}` (`20261019T120000.123456Z`),
  `{date}`, `{seq}` (zero-padded per-buffer file counter), `{uid}` (random
  128-bit id, unique per file).

  `partition_template` (one value per record, at arrival time, UTC):
  `{yyyy}`, `{MM}`, `{dd}`, `{HH}`, `{date}`, `{pipeline_id}`, and any other
  `{name}` or `{dotted.path}` is a record field. Field values are sanitized
  into a single path segment; a missing field renders as `unknown`.

  ## Name length

  Filesystems cap each path component at 255 bytes. Partition values are
  capped at 128 bytes, and rendered directory components at 255, so a
  record can never produce an unwritable directory. The file name itself is
  never shortened (that could drop its `{uid}`); instead `validate_file_name/2`
  rejects a `path_template` whose file name could render longer than the limit.
  """

  @placeholder ~r/\{([A-Za-z0-9_.\-]+)\}/
  @file_placeholders ~w(pipeline_id partition timestamp date seq uid)
  @time_placeholders ~w(yyyy MM dd HH date pipeline_id)
  @max_segment_bytes 128
  @max_name_bytes 255
  @scratch_prefix ".flux-"

  @doc "The expanded base directory every Parquet sink writes under."
  @spec base_dir() :: String.t()
  def base_dir do
    :flux
    |> Application.get_env(Flux.Sink.Adapters.Parquet, [])
    |> Keyword.get(:base_dir, Path.join(System.tmp_dir!(), "flux_parquet"))
    |> Path.expand()
  end

  @doc "The expanded root directory for a sink config (`base_dir/directory`)."
  @spec root(map()) :: {:ok, String.t()} | {:error, :path_escape}
  def root(config), do: resolve(base_dir(), Map.get(config, "directory", ""))

  @doc """
  Joins `relative` onto `root` and returns the expanded path, or
  `{:error, :path_escape}` when the result is not strictly inside `root`.
  """
  @spec resolve(String.t(), String.t()) :: {:ok, String.t()} | {:error, :path_escape}
  def resolve(root, relative) do
    root = Path.expand(root)
    path = root |> Path.join(relative) |> Path.expand()

    if String.starts_with?(path, root <> "/") and not String.contains?(relative, <<0>>),
      do: {:ok, path},
      else: {:error, :path_escape}
  end

  @doc "Validates the sink's `directory` (relative, no `..`)."
  @spec validate_directory(term()) :: :ok | {:error, String.t()}
  def validate_directory(dir) when is_binary(dir) and dir != "" do
    cond do
      Path.type(dir) != :relative ->
        {:error, "directory must be relative to the Parquet base directory"}

      ".." in Path.split(dir) ->
        {:error, "directory must not contain '..'"}

      match?({:error, _}, resolve(base_dir(), dir)) ->
        {:error, "directory must stay inside the Parquet base directory"}

      true ->
        :ok
    end
  end

  def validate_directory(_dir), do: {:error, "directory is required"}

  @doc """
  Validates a template: relative, no `..` segments, and (for `path_template`)
  only known placeholders.
  """
  @spec validate_template(String.t(), :path | :partition) :: :ok | {:error, String.t()}
  def validate_template(template, kind) do
    label = if kind == :path, do: "path_template", else: "partition_template"

    cond do
      String.starts_with?(template, "/") ->
        {:error, "#{label} must be relative"}

      ".." in Path.split(template) ->
        {:error, "#{label} must not contain '..'"}

      kind == :path and unknown_file_placeholders(template) != [] ->
        {:error,
         "path_template has unknown placeholders: " <>
           Enum.join(unknown_file_placeholders(template), ", ")}

      true ->
        :ok
    end
  end

  defp unknown_file_placeholders(template) do
    @placeholder
    |> Regex.scan(template, capture: :all_but_first)
    |> List.flatten()
    |> Enum.reject(&(&1 in @file_placeholders))
    |> Enum.uniq()
  end

  @doc """
  Checks that every file name `path_template` can render fits the filesystem's
  #{@max_name_bytes}-byte name limit, rendering it with the widest value each
  placeholder can take.
  """
  @spec validate_file_name(String.t(), String.t()) :: :ok | {:error, String.t()}
  def validate_file_name(path_template, partition_template) do
    vars = %{
      pipeline_id: String.duplicate("x", @max_segment_bytes),
      now: DateTime.utc_now(),
      seq: 999_999_999,
      uid: uid()
    }

    # A non-empty partition always ends in `/`, closing the path component
    # before it; only its length as a directory matters, and that is capped.
    partition = if String.trim(partition_template, "/") == "", do: "", else: "p/"
    name = path_template |> render_file(Map.put(vars, :partition, partition)) |> Path.basename()

    if byte_size(name) <= @max_name_bytes,
      do: :ok,
      else:
        {:error,
         "path_template file name can render up to #{byte_size(name)} bytes; " <>
           "the limit is #{@max_name_bytes}"}
  end

  @doc "Whether the last component of `path` fits the filesystem's name limit."
  @spec file_name_fits?(String.t()) :: boolean()
  def file_name_fits?(path), do: byte_size(Path.basename(path)) <= @max_name_bytes

  @doc "Whether `template` references `placeholder` (e.g. `\"uid\"`)."
  @spec uses?(String.t(), String.t()) :: boolean()
  def uses?(template, placeholder), do: String.contains?(template, "{#{placeholder}}")

  @doc """
  Renders the partition prefix for one record. Returns `""` for an empty
  template; otherwise a relative directory path ending in `/`.
  """
  @spec render_partition(String.t(), map(), DateTime.t(), term()) :: String.t()
  def render_partition("", _data, _now, _pipeline_id), do: ""

  def render_partition(template, data, now, pipeline_id) do
    rendered =
      Regex.replace(@placeholder, template, fn _match, name ->
        if name in @time_placeholders,
          do: time_value(name, now, pipeline_id),
          else: data |> get_path(name) |> segment()
      end)

    case rendered |> String.trim("/") |> String.split("/") |> Enum.map_join("/", &cap_name/1) do
      "" -> ""
      prefix -> prefix <> "/"
    end
  end

  defp time_value("yyyy", now, _), do: pad(now.year, 4)
  defp time_value("MM", now, _), do: pad(now.month, 2)
  defp time_value("dd", now, _), do: pad(now.day, 2)
  defp time_value("HH", now, _), do: pad(now.hour, 2)
  defp time_value("date", now, _), do: now |> DateTime.to_date() |> Date.to_iso8601()
  defp time_value("pipeline_id", _, pipeline_id), do: segment(pipeline_id)

  @doc """
  Renders the relative file path for one flush. Directory components are capped
  at the name limit; the file name is left whole (see `validate_file_name/2`).
  """
  @spec render_file(String.t(), map()) :: String.t()
  def render_file(template, vars) do
    rendered =
      Regex.replace(@placeholder, template, fn _match, name ->
        case name do
          "pipeline_id" -> segment(vars.pipeline_id)
          "partition" -> vars.partition
          "timestamp" -> Calendar.strftime(vars.now, "%Y%m%dT%H%M%S.%fZ")
          "date" -> vars.now |> DateTime.to_date() |> Date.to_iso8601()
          "seq" -> pad(vars.seq, 6)
          "uid" -> vars.uid
        end
      end)

    # A directory only groups files, so shortening one is harmless.
    {dirs, [name]} = rendered |> String.split("/") |> Enum.split(-1)
    Enum.map_join(dirs, &(cap_name(&1) <> "/")) <> name
  end

  defp cap_name(name), do: take_bytes(name, @max_name_bytes)

  @doc """
  A hidden name for a Flux scratch file: `.flux-<uid><suffix>`. Every temporary
  or probe file the sink creates uses this shape, so readers can ignore
  dotfiles and stale ones can be found by `scratch_glob/1`.
  """
  @spec scratch_name(String.t()) :: String.t()
  def scratch_name(suffix), do: @scratch_prefix <> uid() <> suffix

  @doc "A `Path.wildcard/2` pattern matching `scratch_name(suffix)` names."
  @spec scratch_glob(String.t()) :: String.t()
  def scratch_glob(suffix), do: @scratch_prefix <> "*" <> suffix

  @doc """
  A random 128-bit id (26 lowercase base32 characters). Large enough that a
  `{uid}`-only template never realistically repeats, even across nodes.
  """
  @spec uid() :: String.t()
  def uid, do: 16 |> :crypto.strong_rand_bytes() |> Base.encode32(case: :lower, padding: false)

  defp get_path(data, path) do
    Enum.reduce_while(String.split(path, "."), data, fn key, acc ->
      case acc do
        %{^key => value} -> {:cont, value}
        _ -> {:halt, nil}
      end
    end)
  end

  # Collapses a value into one safe path segment: no separators, no `..`, no
  # control characters, bounded length (in bytes, since that is what the
  # filesystem limits).
  defp segment(value) when is_binary(value) or is_number(value) or is_boolean(value) do
    value
    |> to_string()
    |> String.replace(~r/[\/\\[:cntrl:]]/u, "_")
    |> String.replace("..", "_")
    |> take_bytes(@max_segment_bytes)
    |> case do
      "" -> "unknown"
      "." -> "_"
      segment -> segment
    end
  end

  defp segment(value) when is_atom(value) and not is_nil(value),
    do: segment(Atom.to_string(value))

  defp segment(_value), do: "unknown"

  # The longest prefix of `string` that fits in `max` bytes without splitting a
  # character.
  defp take_bytes(string, max) when byte_size(string) <= max, do: string

  defp take_bytes(string, max) do
    string
    |> String.graphemes()
    |> Enum.reduce_while("", fn grapheme, acc ->
      if byte_size(acc) + byte_size(grapheme) <= max,
        do: {:cont, acc <> grapheme},
        else: {:halt, acc}
    end)
  end

  defp pad(int, width), do: int |> Integer.to_string() |> String.pad_leading(width, "0")
end
