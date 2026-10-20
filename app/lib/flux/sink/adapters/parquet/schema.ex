defmodule Flux.Sink.Adapters.Parquet.Schema do
  @moduledoc """
  Column typing for the Parquet sink: inference, explicit schemas, widening and
  per-value coercion.

  A schema is a map of column name to one of the logical types below. Column
  order in the written file is the sorted column names, so it is deterministic
  regardless of the order keys arrive in.

  | Logical type | Arrow dtype                      | Accepts                                    |
  |--------------|----------------------------------|--------------------------------------------|
  | `:string`    | `:string`                        | binaries                                   |
  | `:integer`   | `{:s, 64}`                       | integers                                   |
  | `:float`     | `{:f, 64}`                       | floats and integers                        |
  | `:boolean`   | `:boolean`                       | booleans                                   |
  | `:date`      | `:date`                          | `Date`, ISO-8601 date strings              |
  | `:timestamp` | `{:naive_datetime, :microsecond}`| `DateTime` (shifted to UTC), `NaiveDateTime`, ISO-8601 strings |
  | `:json`      | `:string`                        | anything; JSON-encoded                     |
  | `:any`       | `:string`                        | anything; binaries as-is, the rest stringified |
  | `:null`      | `:string`                        | `nil` only — a column whose type is not yet known |

  Inferred schemas are strict: a value must already match its column's type
  (with `:integer` silently widening to `:float`, and `:null` adopting the first
  non-nil type). Explicit schemas are lenient: values are parsed into the
  declared type where that is lossless (`"42"` into an integer column), and the
  explicit `"string"` type maps to `:any`.
  """

  @type logical ::
          :string | :integer | :float | :boolean | :date | :timestamp | :json | :any | :null
  @type t :: %{optional(String.t()) => logical()}
  @type row :: %{optional(String.t()) => term()}

  # Explicit-schema type names (the user-facing spelling) to logical types.
  @explicit_types %{
    "string" => :any,
    "integer" => :integer,
    "float" => :float,
    "boolean" => :boolean,
    "date" => :date,
    "timestamp" => :timestamp,
    "json" => :json
  }

  @doc "The type names accepted in an explicit schema."
  @spec explicit_type_names() :: [String.t()]
  def explicit_type_names, do: @explicit_types |> Map.keys() |> Enum.sort()

  @doc """
  Parses an explicit `%{"column" => "type"}` schema from sink config.
  """
  @spec parse_explicit(term()) :: {:ok, t()} | {:error, String.t()}
  def parse_explicit(schema) when is_map(schema) and map_size(schema) > 0 do
    Enum.reduce_while(schema, {:ok, %{}}, fn
      {name, type}, {:ok, acc} when is_binary(name) and name != "" and is_binary(type) ->
        case Map.fetch(@explicit_types, type) do
          {:ok, logical} ->
            {:cont, {:ok, Map.put(acc, name, logical)}}

          :error ->
            {:halt, {:error, "schema column #{inspect(name)} has unknown type #{inspect(type)}"}}
        end

      {name, _type}, _acc ->
        {:halt, {:error, "schema column #{inspect(name)} must map a name to a type name"}}
    end)
  end

  def parse_explicit(_schema), do: {:error, "schema must be a non-empty JSON object"}

  @doc "Infers a schema from a single row."
  @spec infer(row()) :: t()
  def infer(row), do: Map.new(row, fn {name, value} -> {name, type_of(value)} end)

  @doc "Ordered `{name, dtype}` pairs for `Explorer.DataFrame.new/2`."
  @spec dtypes(t()) :: [{String.t(), atom() | tuple()}]
  def dtypes(schema), do: Enum.map(columns(schema), &{&1, dtype(Map.fetch!(schema, &1))})

  @doc "Column names in file order."
  @spec columns(t()) :: [String.t()]
  def columns(schema), do: schema |> Map.keys() |> Enum.sort()

  @doc """
  Fits `row` into an inferred `schema`.

  Returns the (possibly refined) schema and the coerced row on success. A
  `:null` column takes on the first non-nil type seen, and an `:integer` column
  widens to `:float` — both are safe because values already buffered still fit.
  Any other disagreement (a new column, or a value of an incompatible type) is
  a mismatch.
  """
  @spec fit(t(), row()) :: {:ok, t(), row()} | {:mismatch, [String.t()]}
  def fit(schema, row) do
    new_columns = row |> Map.keys() |> Enum.reject(&Map.has_key?(schema, &1))

    if new_columns != [] do
      {:mismatch, Enum.map(Enum.sort(new_columns), &"new column #{inspect(&1)}")}
    else
      fit_values(schema, row)
    end
  end

  defp fit_values(schema, row) do
    {schema, coerced, errors} =
      Enum.reduce(row, {schema, %{}, []}, fn {name, value}, {schema, coerced, errors} ->
        type = Map.fetch!(schema, name)

        case refine(type, value) do
          {:ok, type, value} ->
            {Map.put(schema, name, type), Map.put(coerced, name, value), errors}

          :error ->
            {schema, coerced,
             ["column #{inspect(name)} expected #{type}, got #{type_of(value)}" | errors]}
        end
      end)

    case errors do
      [] -> {:ok, schema, coerced}
      errors -> {:mismatch, Enum.sort(errors)}
    end
  end

  defp refine(:null, nil), do: {:ok, :null, nil}
  defp refine(:null, value), do: refine(type_of(value), value)
  defp refine(:integer, value) when is_float(value), do: {:ok, :float, value}

  defp refine(:any, value) do
    with {:ok, coerced} <- coerce(:any, value), do: {:ok, :any, coerced}
  end

  defp refine(type, value) do
    if type_of(value) in [type, :null] or (type == :float and is_integer(value)) do
      with {:ok, coerced} <- coerce(type, value), do: {:ok, type, coerced}
    else
      :error
    end
  end

  @doc """
  Fits `row` into an explicit (fixed) `schema`: unknown keys are dropped,
  missing keys become `nil`, and values are parsed into their declared types.
  """
  @spec fit_explicit(t(), row()) :: {:ok, row()} | {:error, [String.t()]}
  def fit_explicit(schema, row) do
    {coerced, errors} =
      Enum.reduce(schema, {%{}, []}, fn {name, type}, {coerced, errors} ->
        value = Map.get(row, name)

        case coerce(type, value) do
          {:ok, value} ->
            {Map.put(coerced, name, value), errors}

          :error ->
            {coerced,
             ["column #{inspect(name)} cannot hold #{inspect(value)} as #{type}" | errors]}
        end
      end)

    case errors do
      [] -> {:ok, coerced}
      errors -> {:error, Enum.sort(errors)}
    end
  end

  @doc """
  Widens `schema` so `row` fits: new columns are added with their inferred
  type, and a column whose type conflicts with the row becomes `:any`.
  """
  @spec widen(t(), row()) :: t()
  def widen(schema, row) do
    Enum.reduce(row, schema, fn {name, value}, schema ->
      Map.update(schema, name, type_of(value), &widen_type(&1, type_of(value)))
    end)
  end

  @doc """
  Merges two schemas into one both fit: the union of their columns, with
  conflicting types widened the same way as `widen/2`.
  """
  @spec merge(t(), t()) :: t()
  def merge(a, b), do: Map.merge(a, b, fn _name, ta, tb -> widen_type(ta, tb) end)

  defp widen_type(type, type), do: type
  defp widen_type(:null, type), do: type
  defp widen_type(type, :null), do: type
  defp widen_type(:integer, :float), do: :float
  defp widen_type(:float, :integer), do: :float
  defp widen_type(_, _), do: :any

  @doc "The logical type of a single value."
  @spec type_of(term()) :: logical()
  def type_of(nil), do: :null
  def type_of(value) when is_boolean(value), do: :boolean
  def type_of(value) when is_integer(value), do: :integer
  def type_of(value) when is_float(value), do: :float
  def type_of(value) when is_binary(value), do: :string
  def type_of(%Date{}), do: :date
  def type_of(%DateTime{}), do: :timestamp
  def type_of(%NaiveDateTime{}), do: :timestamp
  def type_of(value) when is_map(value) or is_list(value), do: :json
  def type_of(_value), do: :any

  @doc """
  Coerces `value` into the representation Explorer expects for `type`.
  `nil` is always accepted (every column is nullable).
  """
  @spec coerce(logical(), term()) :: {:ok, term()} | :error
  def coerce(_type, nil), do: {:ok, nil}
  def coerce(:null, _value), do: :error

  def coerce(:string, value) when is_binary(value), do: {:ok, value}
  def coerce(:string, _value), do: :error

  def coerce(:integer, value) when is_integer(value), do: {:ok, value}
  def coerce(:integer, value) when is_binary(value), do: parse_full(Integer.parse(value))
  def coerce(:integer, _value), do: :error

  def coerce(:float, value) when is_float(value), do: {:ok, value}
  def coerce(:float, value) when is_integer(value), do: {:ok, value * 1.0}

  def coerce(:float, value) when is_binary(value) do
    with {:ok, float} <- parse_full(Float.parse(value)), do: {:ok, float * 1.0}
  end

  def coerce(:float, _value), do: :error

  def coerce(:boolean, value) when is_boolean(value), do: {:ok, value}
  def coerce(:boolean, "true"), do: {:ok, true}
  def coerce(:boolean, "false"), do: {:ok, false}
  def coerce(:boolean, _value), do: :error

  def coerce(:date, %Date{} = value), do: {:ok, value}

  def coerce(:date, value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> :error
    end
  end

  def coerce(:date, _value), do: :error

  def coerce(:timestamp, %NaiveDateTime{} = value), do: {:ok, microsecond(value)}

  def coerce(:timestamp, %DateTime{} = value) do
    {:ok, value |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_naive() |> microsecond()}
  end

  def coerce(:timestamp, value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        coerce(:timestamp, datetime)

      {:error, _} ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, naive} -> coerce(:timestamp, naive)
          {:error, _} -> :error
        end
    end
  end

  def coerce(:timestamp, _value), do: :error

  def coerce(:json, value), do: encode_json(value)

  def coerce(:any, value) when is_binary(value), do: {:ok, value}

  def coerce(:any, value) when is_integer(value) or is_float(value) or is_boolean(value),
    do: {:ok, to_string(value)}

  def coerce(:any, %struct{} = value) when struct in [Date, DateTime, NaiveDateTime],
    do: {:ok, struct.to_iso8601(value)}

  def coerce(:any, value), do: encode_json(value)

  defp encode_json(value) do
    case Jason.encode(value) do
      {:ok, json} -> {:ok, json}
      {:error, _} -> {:ok, inspect(value)}
    end
  end

  defp parse_full({number, ""}), do: {:ok, number}
  defp parse_full(_), do: :error

  defp microsecond(%NaiveDateTime{microsecond: {us, _}} = naive),
    do: %{naive | microsecond: {us, 6}}

  defp dtype(:integer), do: {:s, 64}
  defp dtype(:float), do: {:f, 64}
  defp dtype(:boolean), do: :boolean
  defp dtype(:date), do: :date
  defp dtype(:timestamp), do: {:naive_datetime, :microsecond}
  defp dtype(_string_like), do: :string
end
