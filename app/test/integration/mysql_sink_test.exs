defmodule Flux.Integration.MySQLSinkTest do
  @moduledoc """
  Integration tests for the MySQL sink adapter against a real MySQL server.

  Excluded from the default suite (`@moduletag :integration`). To run:

      docker run --rm -d -p 3306:3306 \\
        -e MYSQL_ROOT_PASSWORD=secret -e MYSQL_DATABASE=flux_test mysql:8

      mix test --include integration test/integration/mysql_sink_test.exs

  Override the connection with `MYSQL_TEST_URL` if your server differs.
  """

  use ExUnit.Case, async: false

  @moduletag :integration

  alias Flux.Sink.Adapters.MySQL

  @url System.get_env("MYSQL_TEST_URL", "mysql://root:secret@127.0.0.1:3306/flux_test")
  @table "mysql_sink_test"

  setup_all do
    {:ok, conn} = MyXQL.start_link(url_opts(@url))
    wait_for_mysql(conn)

    MyXQL.query!(conn, "DROP TABLE IF EXISTS #{@table}")

    MyXQL.query!(conn, """
    CREATE TABLE #{@table} (
      id INT PRIMARY KEY,
      event_type VARCHAR(255),
      payload JSON,
      inserted_at DATETIME,
      updated_at DATETIME
    )
    """)

    on_exit(fn ->
      {:ok, c} = MyXQL.start_link(url_opts(@url))
      MyXQL.query!(c, "DROP TABLE IF EXISTS #{@table}")
    end)

    %{conn: conn}
  end

  setup %{conn: conn} do
    MyXQL.query!(conn, "TRUNCATE TABLE #{@table}")
    :ok
  end

  # MySQL can take 15-30s to initialize on first boot. Wait for it to accept
  # connections so the suite doesn't fail just because the container is still
  # warming up.
  defp wait_for_mysql(conn, deadline \\ 30) do
    case MyXQL.query(conn, "SELECT 1") do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        if deadline <= 0 do
          raise "MySQL not reachable at #{@url}: #{inspect(reason)}"
        else
          Process.sleep(1000)
          wait_for_mysql(conn, deadline - 1)
        end
    end
  end

  defp url_opts(url) do
    uri = URI.parse(url)
    [user, pass] = String.split(uri.userinfo, ":", parts: 2)

    [
      hostname: uri.host,
      port: uri.port || 3306,
      username: user,
      password: pass,
      database: String.trim_leading(uri.path, "/")
    ]
  end

  defp base_config(extra \\ %{}) do
    Map.merge(
      %{
        "database_url" => @url,
        "table" => @table,
        "columns" => %{"id" => "id", "type" => "event_type", "payload" => "payload"}
      },
      extra
    )
  end

  defp count(conn), do: MyXQL.query!(conn, "SELECT COUNT(*) FROM #{@table}").rows |> hd() |> hd()

  test "plain insert lands a row", %{conn: conn} do
    data = %{"id" => 1, "type" => "user.created", "payload" => %{"name" => "ada"}}
    assert :ok = MySQL.deliver(data, base_config(), [])

    assert count(conn) == 1
    %{rows: [[type, payload]]} = MyXQL.query!(conn, "SELECT event_type, payload FROM #{@table}")
    assert type == "user.created"
    # The map is encoded to JSON on insert; MySQL stores it as a JSON column and
    # MyXQL decodes it back to a map on read.
    assert payload == %{"name" => "ada"}
  end

  test "duplicate key raises by default" do
    data = %{"id" => 1, "type" => "a", "payload" => %{}}
    assert :ok = MySQL.deliver(data, base_config(), [])
    assert {:error, {:mysql_error, _}} = MySQL.deliver(data, base_config(), [])
  end

  test "on_conflict ignore skips duplicates", %{conn: conn} do
    config = base_config(%{"on_conflict" => "ignore"})
    assert :ok = MySQL.deliver(%{"id" => 1, "type" => "a", "payload" => %{}}, config, [])
    assert :ok = MySQL.deliver(%{"id" => 1, "type" => "b", "payload" => %{}}, config, [])

    assert count(conn) == 1
    %{rows: [[type]]} = MyXQL.query!(conn, "SELECT event_type FROM #{@table}")
    assert type == "a"
  end

  test "on_conflict update upserts the row", %{conn: conn} do
    config = base_config(%{"on_conflict" => "update"})
    assert :ok = MySQL.deliver(%{"id" => 1, "type" => "a", "payload" => %{}}, config, [])
    assert :ok = MySQL.deliver(%{"id" => 1, "type" => "b", "payload" => %{}}, config, [])

    assert count(conn) == 1
    %{rows: [[type]]} = MyXQL.query!(conn, "SELECT event_type FROM #{@table}")
    assert type == "b"
  end

  test "insert into a missing table returns a mysql_error" do
    config = base_config(%{"table" => "no_such_table"})
    assert {:error, {:mysql_error, _}} = MySQL.deliver(%{"id" => 1}, config, [])
  end

  test "test_connection succeeds against a reachable server" do
    assert :ok = MySQL.test_connection(base_config())
  end

  test "test_connection fails against an unreachable server" do
    config = base_config(%{"database_url" => "mysql://root:secret@127.0.0.1:3307/flux_test"})
    assert {:error, _reason} = MySQL.test_connection(config)
  end
end
