# Parquet File Sink

The Parquet sink writes pipeline records as columnar
[Apache Parquet](https://parquet.apache.org/) files, ready for DuckDB, Spark,
Athena, BigQuery external tables, pandas/Polars and other analytics and ML tools.

> **Community feature.** Parquet is available on every tier, including the free
> Community edition.

Unlike the other sinks, Parquet delivery is **buffered**. Records collect in
memory and are written to a file when one of these happens (see
[Rotation](#rotation-and-durability)):

- the row threshold is reached;
- the time threshold passes;
- the schema changes;
- Flux shuts down.

Files are written to the **local filesystem** under the server's Parquet base
directory. To land them in object storage, mount a bucket at that directory (see
[Writing to S3, GCS or Azure](#writing-to-s3-gcs-or-azure)).

## Configuration

| Field | Required | Description |
| --- | --- | --- |
| `directory` | yes | Folder for this sink, **relative** to the Parquet base directory. Absolute paths and `..` are rejected. |
| `partition_template` | no | Hive-style partition folders, e.g. `year={yyyy}/month={MM}/`. Default: none. |
| `path_template` | no | File path inside `directory`. Default: `{pipeline_id}/{partition}part-{timestamp}-{seq}-{uid}.parquet`. |
| `compression` | no | `snappy` (default), `zstd`, `gzip` or `none`. |
| `compression_level` | no | `gzip` 1–9 or `zstd` -7–22. Only valid with those two codecs. |
| `max_rows` | no | Start a new file after this many rows (default `100000`, max `10000000`). |
| `max_interval_seconds` | no | Start a new file once the current one has been open this long (default `600`). |
| `schema` | no | Explicit schema: a JSON object mapping column name to type. Leave blank to infer it. |
| `schema_mode` | no | What to do when an inferred schema changes: `rotate` (default) or `strict`. |

### The base directory

The operator sets the base directory, not the sink, so a sink can never write
outside it. Every rendered path is checked against it before anything is written.

| Environment | Default base directory |
| --- | --- |
| Release / Docker image | `/app/data/parquet` (created and owned by the runtime user) |
| Development | `app/tmp/parquet` |

To override it, set `FLUX_PARQUET_BASE_DIR`. The directory must be writable by
the Flux process.

### Path template placeholders

`path_template` is rendered once per file:

- `{pipeline_id}`: the pipeline that produced the rows
- `{partition}`: the rendered `partition_template` (empty when none is set)
- `{timestamp}`: when the file is written, in UTC (`20261019T120000.123456Z`)
- `{date}`: when the file is written (`2026-10-19`)
- `{seq}`: a zero-padded counter of files written by this buffer (`000001`)
- `{uid}`: a random 128-bit id (26 characters), unique per file

The template must end in `.parquet`. It must include `{uid}` or `{timestamp}` so
each file gets a distinct name. Flux never replaces an existing file. If a name is
somehow already taken, Flux picks a fresh one and tries again, without re-encoding
the file. If you set `partition_template`, it must also include `{partition}`.

Filesystems limit each file or folder name to 255 bytes. Flux checks the file name
when you save the sink: a `path_template` whose file name could render longer than
that (counting `{pipeline_id}` at its 128-byte maximum) is rejected. Folder names
are never rejected; any that would be too long are shortened to 255 bytes.

### Partition template placeholders

`partition_template` is rendered **per record**, in UTC, when the record arrives.
Each distinct partition gets its own file:

- `{yyyy}`, `{MM}`, `{dd}`, `{HH}`: year, month, day and hour
- `{date}`: `2026-10-19`
- `{pipeline_id}`: the pipeline id
- any other `{name}` or `{dotted.path}`: a field of the record, such as `{region}`
  or `{customer.tier}`

Field values are sanitized into a single folder name: path separators, `..` and
control characters become `_`, and values are capped at 128 bytes (fewer characters
for non-ASCII text, never splitting a character). A missing
field, or one holding an object or a list, renders as `unknown`.

Example: daily partitions per region.

```
partition_template: region={region}/date={date}/
→ events/42/region=eu-west/date=2026-10-19/part-20261019T120000.123456Z-000001-1a2b3c4d.parquet
```

Partitioning on a field with many distinct values opens one in-memory buffer per
value. To bound memory, Flux writes out the oldest open partition once more than
500 are open.

## Compression

| Codec | Notes |
| --- | --- |
| `snappy` | Default. Fast, with a moderate compression ratio. Reads well everywhere. |
| `zstd` | A better ratio at similar speed. Set `compression_level` (higher means smaller and slower). |
| `gzip` | The most widely supported codec, but slower. Set `compression_level` 1–9. |
| `none` | Uncompressed. |

## Schema

### Inferred (default)

With no explicit `schema`, the first record to reach a new file sets that file's
schema. The record's top-level fields become columns, sorted by name.

| Record value | Parquet column |
| --- | --- |
| string | `string` |
| integer | `int64` |
| float | `double` (an integer column that later receives a float widens to `double`) |
| boolean | `boolean` |
| object or array | `string` containing the JSON text |
| `null` | nullable; the column takes the type of the first non-null value |

A missing field is written as `null`. If a later record has a **new field**, or a
value of an **incompatible type**, `schema_mode` decides what happens:

- `rotate` (default): Flux writes the current file and starts a new one with the
  **widened** schema. The new schema adds the new columns, and any column whose type
  conflicts becomes `string`. Later files keep the widened schema, so a stream with
  occasional extra fields doesn't produce a new file for every record.
- `strict`: Flux rejects the record and logs a `schema_mismatch` error. The schema
  stays locked to the first record's shape until the buffer restarts, which happens
  when Flux restarts or the sink has been idle for 5 minutes.

### Explicit

Set `schema` to fix the columns and their types:

```json
{"id": "integer", "email": "string", "amount": "float", "created_at": "timestamp"}
```

| Type | Parquet column | Accepts |
| --- | --- | --- |
| `string` | `string` | any value. Numbers and booleans are stringified; objects become JSON. |
| `integer` | `int64` | integers and integer strings (`"42"`) |
| `float` | `double` | numbers and numeric strings |
| `boolean` | `boolean` | `true` / `false` and `"true"` / `"false"` |
| `date` | `date` | ISO-8601 dates (`2026-10-19`) |
| `timestamp` | `timestamp[µs]` | ISO-8601 date-times. Values with an offset are converted to UTC. |
| `json` | `string` | any value, stored as JSON text |

With an explicit schema:

- Fields not in the schema are **dropped**.
- Missing fields are written as `null`.
- A value that can't be converted to its column's type is rejected with a
  `schema_mismatch` error.

`schema_mode` does not apply.

## Rotation and durability

A file is written when **any** of these happens:

- its partition reaches `max_rows`;
- it has been open for `max_interval_seconds` (checked every quarter interval,
  at most every 5 seconds);
- an inferred schema changes in `rotate` mode;
- the sink's config is edited (buffered rows are written with the old settings
  first);
- Flux shuts down normally.

Each file is written to a hidden temporary file (`.flux-<id>.tmp`) and then
renamed into place. Readers that list the directory never see a half-written
file, so ignore dotfiles when you scan it.

If a write is interrupted (a crash or `SIGKILL` mid-write), its temporary file is
left behind. When a sink's buffer starts, Flux removes `.flux-*.tmp` files older
than one hour anywhere under that sink's `directory`. This happens in the
background, once per sink directory each time Flux starts. To change the age, set
`config :flux, Flux.Sink.Adapters.Parquet, temp_file_grace_ms: <ms>`. Keep it
longer than your slowest write, because the sweep can't tell another node's
in-progress write from an abandoned one.

> **Durability.** Rows waiting in the buffer are held **in memory**. On a normal
> shutdown or restart they are written out, and shutdown waits for that to finish.
> Give your orchestrator enough grace time for it (e.g. Kubernetes
> `terminationGracePeriodSeconds`). To cap the wait instead, set
> `config :flux, Flux.Sink.Adapters.Parquet, shutdown_timeout: <ms>`. A hard kill (`SIGKILL`, OOM, power
> loss) loses up to one buffer's worth of rows for each sink and pipeline. This
> matches the other sinks, where a sink failure does not cause the source message
> to be retried. If you can't afford that window, lower `max_rows` and
> `max_interval_seconds`.

If a write fails (for example, the disk is full or a mount has dropped), Flux logs
an error naming the sink, the pipeline and the number of rows lost. It also emits
a `[:flux, :sink, :parquet, :flush]` telemetry event with `status: :error`.

## Writing to S3, GCS or Azure

The Parquet sink writes to a filesystem path. To land files in object storage,
point the base directory at a mounted bucket:

| Storage | Mount tool | Example |
| --- | --- | --- |
| Amazon S3 | [Mountpoint for Amazon S3](https://github.com/awslabs/mountpoint-s3) | `mount-s3 my-lake /mnt/lake` |
| Google Cloud Storage | [Cloud Storage FUSE](https://cloud.google.com/storage/docs/gcs-fuse) | `gcsfuse my-lake /mnt/lake` |
| Azure Blob Storage | [BlobFuse2](https://github.com/Azure/azure-storage-fuse) | `blobfuse2 mount /mnt/lake --config-file=cfg.yaml` |
| Kubernetes | The CSI driver for each of the above | Mount the volume at `/app/data/parquet` |

Then start Flux with `FLUX_PARQUET_BASE_DIR=/mnt/lake` (or mount the volume
directly at `/app/data/parquet` in the container).

Flux writes each file under a temporary name and then **renames** it into place.
Not every mount tool supports this:

- Cloud Storage FUSE and BlobFuse2 support renames. They are a copy followed by a
  delete, so readers should ignore dotfiles.
- Mountpoint for Amazon S3 does **not** support renames on general-purpose
  buckets. With S3, write to a local volume instead and sync it to the bucket on a
  schedule, e.g. `aws s3 sync /app/data/parquet s3://my-lake --exclude "*/.*"`.

The sync approach also works with any storage if you want only finished files to
ever appear in the bucket.

## Test connection

**Test connection** on the sink form checks that `directory` resolves inside the
base directory. It creates the directory, then writes and deletes a small probe
file. It reports a path escape, or the filesystem error (for example `eacces` or
`erofs`), when the location isn't writable.
