# MySQL Sink

The MySQL sink writes pipeline records into a MySQL table. It is a **Community**
connector (available on all tiers) and supports MySQL **5.7** and **8.0**.

MySQL is always an **external** destination — Flux's own database is Postgres, so
every MySQL sink needs connection details. Before configuring one, read
[Connecting to external databases](external-databases.md) — a sink can save
successfully yet fail to deliver if the network path to your database is blocked.

## Configuration

| Field | Required | Description |
| --- | --- | --- |
| `database_url` | yes | `mysql://user:pass@host:3306/database` |
| `table` | yes | Target table name |
| `columns` | yes | Map of `source field → column name` (see below) |
| `on_conflict` | no | `raise` (default), `ignore`, or `update` |
| `ssl` | no | `true` to connect over TLS (default `false`) |
| `max_retries` | no | Retries on deadlock / lock-wait / connection loss (default `3`) |
| `pool_size` | no | Connection pool size (default `5`) |

### Column mapping

`columns` maps fields in the incoming record to columns in the table. Keys are
dot-separated paths into the record, so nested values can be pulled out:

```json
{
  "event_type": "type",
  "payload.user_id": "user_id",
  "payload": "raw_payload"
}
```

- `inserted_at` and `updated_at` are added automatically if you don't map them.
- Map and list values are JSON-encoded before insert, so they land cleanly in
  `JSON` or `TEXT` columns on both MySQL 5.7 and 8.0.

### Conflict handling

| Mode | SQL | Behaviour |
| --- | --- | --- |
| `raise` | `INSERT` | A duplicate key raises an error (default) |
| `ignore` | `INSERT IGNORE` | Duplicate-key rows are silently skipped |
| `update` | `INSERT ... ON DUPLICATE KEY UPDATE col = VALUES(col)` | Upsert — existing row is updated |

`update` and `ignore` require a `PRIMARY KEY` or `UNIQUE` index on the table for
the conflict to be detected.

## Example

```json
{
  "type": "mysql",
  "database_url": "mysql://flux:s3cret@db.internal:3306/analytics",
  "table": "events",
  "columns": {
    "event_type": "type",
    "payload.user_id": "user_id",
    "payload": "raw_payload"
  },
  "on_conflict": "update",
  "ssl": true
}
```

## Performance

Delivery is **single-record**: each pipeline message opens a fresh connection,
inserts one row, and closes it (mirroring the Postgres external sink). This is
fine for typical event throughput. High-volume batch loading (multi-row inserts)
is a separate, batched-delivery effort and is not part of this adapter.

## Testing locally

The adapter's unit tests run with the normal suite. The integration tests need a
real MySQL and are excluded by default (`@tag :integration`):

```bash
cid=$(docker run --rm -d -p 3306:3306 \
  -e MYSQL_ROOT_PASSWORD=secret -e MYSQL_DATABASE=flux_test mysql:8)

# MySQL takes ~15-30s to initialize on first boot — wait until it accepts
# connections before running the tests, or setup_all will fail with
# "connection not available".
until docker exec "$cid" mysqladmin ping -uroot -psecret --silent 2>/dev/null; do sleep 2; done

mix test --include integration test/integration/mysql_sink_test.exs
```

Set `MYSQL_TEST_URL` to point at a different server.
