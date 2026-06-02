defmodule Flux.Sink.Adapters.Postgres do
  @moduledoc """
  Postgres/SQL sink adapter using Ecto.

  Inserts pipeline data into a PostgreSQL table.

  ## Configuration

      %{
        "type" => "postgres",
        "mode" => "internal",                        # "internal" or "external"
        "table" => "events",                         # Required
        "columns" => %{                              # Required
          "event_type" => "type",                    # data_field => column_name
          "payload.user_id" => "user_id",            # supports nested fields
          "timestamp" => "created_at"
        },
        "on_conflict" => "nothing",                  # Optional: "nothing", "replace_all", "raise"
        "conflict_target" => ["id"]                  # Optional: columns for conflict detection
      }

  ## External Mode

  For external databases, add connection config:

      %{
        "type" => "postgres",
        "mode" => "external",
        "database_url" => "postgres://user:pass@host:5432/db",
        "pool_size" => 5,                            # Optional, default: 5
        ...
      }

  ## Column Mapping

  The `columns` map specifies how data fields map to database columns:

  - Keys are dot-separated paths in the source data (e.g., `"payload.user_id"`)
  - Values are the target column names

  Timestamps (`inserted_at`, `updated_at`) are automatically added if not mapped.

  """

  @behaviour Flux.Sink.Adapter

  require Logger

  @default_pool_size 5

  @impl Flux.Sink.Adapter
  def deliver(data, config, _opts) do
    table = Map.fetch!(config, "table")
    columns = Map.fetch!(config, "columns")
    mode = Map.get(config, "mode", "internal")

    row = build_row(data, columns)

    case mode do
      "internal" -> insert_internal(table, row, config)
      "external" -> insert_external(table, row, config)
    end
  end

  @impl Flux.Sink.Adapter
  def validate_config(config) do
    errors = []

    errors =
      if Map.has_key?(config, "table") do
        errors
      else
        ["table is required" | errors]
      end

    errors =
      case Map.get(config, "table") do
        nil -> errors
        t when is_binary(t) and byte_size(t) > 0 -> errors
        _ -> ["table must be a non-empty string" | errors]
      end

    errors =
      if Map.has_key?(config, "columns") do
        errors
      else
        ["columns mapping is required" | errors]
      end

    errors =
      case Map.get(config, "columns") do
        nil -> errors
        c when is_map(c) and map_size(c) > 0 -> errors
        _ -> ["columns must be a non-empty map" | errors]
      end

    errors =
      case Map.get(config, "mode", "internal") do
        "internal" ->
          errors

        "external" ->
          if Map.has_key?(config, "database_url") do
            errors
          else
            ["database_url is required for external mode" | errors]
          end

        mode ->
          ["mode must be 'internal' or 'external', got: #{mode}" | errors]
      end

    errors =
      case Map.get(config, "on_conflict") do
        nil ->
          errors

        "nothing" ->
          errors

        "replace_all" ->
          errors

        "raise" ->
          errors

        other ->
          ["on_conflict must be 'nothing', 'replace_all', or 'raise', got: #{other}" | errors]
      end

    if errors == [] do
      :ok
    else
      {:error, Enum.reverse(errors)}
    end
  end

  @impl Flux.Sink.Adapter
  def test_connection(config) do
    mode = Map.get(config, "mode", "internal")

    case mode do
      "internal" ->
        case Flux.Repo.query("SELECT 1") do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      "external" ->
        database_url = Map.fetch!(config, "database_url")
        opts = parse_database_url(database_url)

        case Postgrex.start_link(opts) do
          {:ok, conn} ->
            result = Postgrex.query(conn, "SELECT 1", [])
            GenServer.stop(conn)

            case result do
              {:ok, _} -> :ok
              {:error, reason} -> {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp build_row(data, columns) do
    now = DateTime.utc_now()

    mapped =
      columns
      |> Enum.map(fn {data_field, column_name} ->
        value = get_nested_value(data, data_field)
        {String.to_atom(column_name), value}
      end)
      |> Map.new()

    # Add timestamps if not already mapped
    mapped
    |> maybe_put_default(:inserted_at, now)
    |> maybe_put_default(:updated_at, now)
  end

  defp maybe_put_default(map, key, value) do
    if Map.has_key?(map, key) do
      map
    else
      Map.put(map, key, value)
    end
  end

  defp get_nested_value(data, field) when is_binary(field) do
    keys = String.split(field, ".")

    Enum.reduce_while(keys, data, fn key, acc ->
      case acc do
        %{^key => value} -> {:cont, value}
        _ -> {:halt, nil}
      end
    end)
  end

  defp insert_internal(table, row, config) do
    conflict_opts = build_conflict_opts(config)

    try do
      case Flux.Repo.insert_all(table, [row], conflict_opts) do
        {1, _} ->
          Logger.debug("Postgres sink inserted row", table: table)
          :ok

        {0, _} ->
          Logger.debug("Postgres sink row ignored (conflict)", table: table)
          {:ok, :conflict_ignored}

        other ->
          {:error, {:unexpected_result, other}}
      end
    rescue
      e in Postgrex.Error ->
        Logger.error("Postgres sink insert failed",
          table: table,
          error: Exception.message(e)
        )

        {:error, {:postgres_error, Exception.message(e)}}

      e ->
        Logger.error("Postgres sink insert failed",
          table: table,
          error: Exception.message(e)
        )

        {:error, {:insert_error, Exception.message(e)}}
    end
  end

  defp insert_external(table, row, config) do
    database_url = Map.fetch!(config, "database_url")
    pool_size = Map.get(config, "pool_size", @default_pool_size)

    opts =
      parse_database_url(database_url)
      |> Keyword.put(:pool_size, pool_size)

    case Postgrex.start_link(opts) do
      {:ok, conn} ->
        result = execute_insert(conn, table, row, config)
        GenServer.stop(conn)
        result

      {:error, reason} ->
        Logger.error("Postgres sink connection failed",
          reason: inspect(reason)
        )

        {:error, {:connection_failed, reason}}
    end
  end

  defp execute_insert(conn, table, row, _config) do
    {columns, values} =
      row
      |> Map.to_list()
      |> Enum.unzip()

    placeholders =
      1..length(columns)
      |> Enum.map(fn i -> "$#{i}" end)
      |> Enum.join(", ")

    column_names =
      columns
      |> Enum.map(&to_string/1)
      |> Enum.join(", ")

    query = "INSERT INTO #{table} (#{column_names}) VALUES (#{placeholders})"

    case Postgrex.query(conn, query, values) do
      {:ok, %Postgrex.Result{num_rows: 1}} ->
        Logger.debug("Postgres sink inserted row (external)", table: table)
        :ok

      {:ok, result} ->
        {:error, {:unexpected_result, result}}

      {:error, %Postgrex.Error{} = error} ->
        Logger.error("Postgres sink insert failed (external)",
          table: table,
          error: Exception.message(error)
        )

        {:error, {:postgres_error, Exception.message(error)}}
    end
  end

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
      port: uri.port || 5432,
      username: username,
      password: password,
      database: database
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp build_conflict_opts(config) do
    case Map.get(config, "on_conflict", "raise") do
      "nothing" ->
        [on_conflict: :nothing]

      "replace_all" ->
        target = Map.get(config, "conflict_target", [])
        target_atoms = Enum.map(target, &String.to_atom/1)
        [on_conflict: :replace_all, conflict_target: target_atoms]

      "raise" ->
        []
    end
  end
end
