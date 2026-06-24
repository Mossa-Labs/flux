defmodule Flux.Sink.Adapters.MySQL do
  @moduledoc """
  MySQL sink adapter using MyXQL.

  Inserts pipeline data into a MySQL table (MySQL 5.7 and 8.0). Unlike the
  Postgres adapter there is no "internal" mode — Flux's own repository is
  Postgres, so MySQL is always an **external** destination and connection
  details are required.

  ## Configuration

      %{
        "type" => "mysql",
        "database_url" => "mysql://user:pass@host:3306/db",  # Required
        "table" => "events",                                  # Required
        "columns" => %{                                       # Required
          "event_type" => "type",                             # data_field => column_name
          "payload.user_id" => "user_id",                     # supports nested fields
          "timestamp" => "created_at"
        },
        "on_conflict" => "update",   # Optional: "raise" (default) | "ignore" | "update"
        "ssl" => false,              # Optional: enable TLS
        "max_retries" => 3,          # Optional: retries on deadlock / lock-wait / conn loss
        "pool_size" => 5             # Optional, default: 5
      }

  ## Column Mapping

  The `columns` map specifies how data fields map to database columns:

    - Keys are dot-separated paths in the source data (e.g. `"payload.user_id"`)
    - Values are the target column names

  Timestamps (`inserted_at`, `updated_at`) are automatically added if not mapped.

  Map/list values are JSON-encoded before insert so they land cleanly in JSON or
  TEXT columns across MySQL 5.7 and 8.0.

  ## Conflict handling

    - `"raise"` (default) — plain `INSERT`; a duplicate key raises an error
    - `"ignore"` — `INSERT IGNORE`; duplicate-key rows are silently skipped
    - `"update"` — `INSERT ... ON DUPLICATE KEY UPDATE col = VALUES(col)` upsert

  ## Performance note

  Delivery is single-record and opens a fresh connection per call (mirroring the
  Postgres external path). This is fine for typical event throughput; high-volume
  batch loading is a separate (batched-delivery) effort tracked outside this adapter.
  """

  @behaviour Flux.Sink.Adapter

  require Logger

  @default_pool_size 5
  @default_max_retries 3
  @default_port 3306
  @retry_backoff_ms 100

  # MySQL server error codes worth retrying.
  @deadlock 1213
  @lock_wait_timeout 1205

  @impl Flux.Sink.Adapter
  def deliver(data, config, _opts) do
    table = Map.fetch!(config, "table")
    columns = Map.fetch!(config, "columns")
    max_retries = Map.get(config, "max_retries", @default_max_retries)

    row = build_row(data, columns)
    {column_names, values} = row |> Map.to_list() |> Enum.unzip()
    coerced = Enum.map(values, &coerce_value/1)
    sql = build_insert_sql(table, column_names, Map.get(config, "on_conflict", "raise"))

    with_retry(fn -> insert(table, sql, coerced, config) end, max_retries)
  end

  @impl Flux.Sink.Adapter
  def validate_config(config) do
    Flux.Sink.Validation.run(config, [
      &validate_table/1,
      &validate_columns/1,
      &validate_database_url/1,
      &validate_on_conflict/1
    ])
  end

  @impl Flux.Sink.Adapter
  def test_connection(config) do
    database_url = Map.fetch!(config, "database_url")

    case start_connection(config, database_url) do
      {:ok, conn} ->
        result = MyXQL.query(conn, "SELECT 1")
        GenServer.stop(conn)

        case result do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Validation ──────────────────────────────────────────────────────────

  defp validate_table(config) do
    case Map.get(config, "table") do
      nil -> {:error, "table is required"}
      t when is_binary(t) and byte_size(t) > 0 -> :ok
      _ -> {:error, "table must be a non-empty string"}
    end
  end

  defp validate_columns(config) do
    case Map.get(config, "columns") do
      nil -> {:error, "columns mapping is required"}
      c when is_map(c) and map_size(c) > 0 -> :ok
      _ -> {:error, "columns must be a non-empty map"}
    end
  end

  defp validate_database_url(config) do
    case Map.get(config, "database_url") do
      url when is_binary(url) and byte_size(url) > 0 ->
        case URI.parse(url) do
          %URI{scheme: "mysql", host: host} when is_binary(host) -> :ok
          _ -> {:error, "database_url must be a mysql:// URL with a host"}
        end

      _ ->
        {:error, "database_url is required"}
    end
  end

  defp validate_on_conflict(config) do
    case Map.get(config, "on_conflict") do
      target when target in [nil, "raise", "ignore", "update"] ->
        :ok

      other ->
        {:error, "on_conflict must be 'raise', 'ignore', or 'update', got: #{other}"}
    end
  end

  # ── SQL generation (pure — unit-tested without a DB) ────────────────────

  @doc """
  Builds the parameterized `INSERT` statement for the given table, ordered
  column names, and conflict strategy. Returns the SQL string with `?`
  placeholders; values must be supplied in the same order as `column_names`.
  """
  @spec build_insert_sql(String.t(), [String.t() | atom()], String.t()) :: String.t()
  def build_insert_sql(table, column_names, on_conflict) do
    cols = Enum.map(column_names, &to_string/1)
    quoted_cols = Enum.map_join(cols, ", ", &quote_ident/1)
    placeholders = Enum.map_join(cols, ", ", fn _ -> "?" end)
    verb = if on_conflict == "ignore", do: "INSERT IGNORE", else: "INSERT"

    base =
      "#{verb} INTO #{quote_ident(table)} (#{quoted_cols}) VALUES (#{placeholders})"

    case on_conflict do
      "update" -> base <> " ON DUPLICATE KEY UPDATE " <> update_clause(cols)
      _ -> base
    end
  end

  defp update_clause(cols) do
    Enum.map_join(cols, ", ", fn col ->
      "#{quote_ident(col)} = VALUES(#{quote_ident(col)})"
    end)
  end

  # Backtick-quote an identifier, escaping any embedded backticks. Column and
  # table names originate from user-supplied sink config.
  defp quote_ident(ident) do
    escaped = ident |> to_string() |> String.replace("`", "``")
    "`" <> escaped <> "`"
  end

  # ── Row building / coercion ─────────────────────────────────────────────

  defp build_row(data, columns) do
    now = DateTime.utc_now()

    # Column names stay strings — they come from user config and interning them
    # as atoms would leak the atom table.
    mapped =
      columns
      |> Enum.map(fn {data_field, column_name} ->
        {column_name, get_nested_value(data, data_field)}
      end)
      |> Map.new()

    mapped
    |> maybe_put_default("inserted_at", now)
    |> maybe_put_default("updated_at", now)
  end

  defp maybe_put_default(map, key, value) do
    if Map.has_key?(map, key), do: map, else: Map.put(map, key, value)
  end

  defp get_nested_value(data, field) when is_binary(field) do
    field
    |> String.split(".")
    |> Enum.reduce_while(data, fn key, acc ->
      case acc do
        %{^key => value} -> {:cont, value}
        _ -> {:halt, nil}
      end
    end)
  end

  @doc """
  Coerces a value for a MySQL parameter. Maps and lists are JSON-encoded so they
  land cleanly in JSON/TEXT columns (MyXQL won't encode them); structs (e.g.
  `DateTime`) and scalars pass through to MyXQL's own encoding.
  """
  @spec coerce_value(term()) :: term()
  def coerce_value(value) when is_map(value) and not is_struct(value), do: Jason.encode!(value)
  def coerce_value(value) when is_list(value), do: Jason.encode!(value)
  def coerce_value(value), do: value

  # ── Connection / execution ──────────────────────────────────────────────

  defp insert(table, sql, values, config) do
    database_url = Map.fetch!(config, "database_url")

    case start_connection(config, database_url) do
      {:ok, conn} ->
        result = execute_insert(conn, table, sql, values)
        GenServer.stop(conn)
        result

      {:error, reason} ->
        Logger.error("MySQL sink connection failed", reason: inspect(reason))
        {:error, {:connection_failed, reason}}
    end
  end

  defp execute_insert(conn, table, sql, values) do
    case MyXQL.query(conn, sql, values) do
      {:ok, %MyXQL.Result{num_rows: rows}} when rows in [0, 1, 2] ->
        # 0 = INSERT IGNORE skipped a duplicate; 2 = ON DUPLICATE KEY updated a row.
        Logger.debug("MySQL sink inserted row", table: table, affected: rows)
        :ok

      {:ok, %MyXQL.Result{} = result} ->
        {:error, {:unexpected_result, result}}

      {:error, %MyXQL.Error{} = error} ->
        Logger.error("MySQL sink insert failed", table: table, error: Exception.message(error))
        {:error, {:mysql_error, error}}
    end
  end

  defp start_connection(config, database_url) do
    opts =
      database_url
      |> parse_database_url()
      |> Keyword.put(:pool_size, Map.get(config, "pool_size", @default_pool_size))
      |> maybe_put_ssl(Map.get(config, "ssl", false))

    MyXQL.start_link(opts)
  end

  defp maybe_put_ssl(opts, true), do: Keyword.put(opts, :ssl, true)
  defp maybe_put_ssl(opts, _), do: opts

  defp parse_database_url(url) do
    uri = URI.parse(url)

    {username, password} =
      case uri.userinfo do
        nil -> {nil, nil}
        info -> String.split(info, ":", parts: 2) |> then(&{Enum.at(&1, 0), Enum.at(&1, 1)})
      end

    database = String.trim_leading(uri.path || "", "/")

    [
      hostname: uri.host,
      port: uri.port || @default_port,
      username: username,
      password: password,
      database: database
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  # ── Retry on transient errors ───────────────────────────────────────────

  defp with_retry(fun, retries_left) do
    case fun.() do
      {:error, reason} = error ->
        if retries_left > 0 and retryable?(reason) do
          Process.sleep(@retry_backoff_ms)
          with_retry(fun, retries_left - 1)
        else
          error
        end

      ok ->
        ok
    end
  end

  defp retryable?({:connection_failed, _}), do: true

  defp retryable?({:mysql_error, %MyXQL.Error{mysql: %{code: code}}})
       when code in [@deadlock, @lock_wait_timeout],
       do: true

  defp retryable?(_), do: false
end
