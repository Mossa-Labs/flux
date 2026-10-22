# Google Cloud Storage Sink

Google Cloud Storage (GCS) is a **Pro** sink that batches pipeline records into
newline-delimited JSON or Parquet objects in a GCS bucket.

> **Pro feature.** On the Community edition the GCS sink is gated: the type appears
> in the UI marked *Pro* and any saved config is rejected with an upgrade prompt.
> The real adapter ships in the Flux Pro / Enterprise edition. Activate a license to
> enable it. See [pricing](https://fluxdata.tech/pricing.html).

Flux uploads objects over **HTTPS** through the Cloud Storage JSON API, so — like the
[BigQuery](bigquery.md) and [S3](s3.md) sinks — it is an **outbound** integration:
the sink can save with valid credentials and still fail to deliver if the network
path to Google's APIs is blocked.

Unlike the S3 sink, which writes one object per record, the GCS sink **buffers**
records and writes them as one object per batch (see [Batching](#batching)).

## Configuration

| Field | Required | Description |
| --- | --- | --- |
| `bucket` | yes | Destination bucket name. |
| `object_template` | no | Object-name template (default `{pipeline_id}/{date}/{timestamp}-{uid}`). The file extension is appended for you. |
| `format` | no | `ndjson` (default) or `parquet`. |
| `compression` | no | For `ndjson`: `gzip` (default) or `none`. For `parquet`: `snappy` (default), `zstd`, `gzip` or `none`. |
| `credentials` | no | Service-account key JSON. If blank, Flux falls back to Application Default Credentials (see [Authentication](#authentication)). |
| `max_records` | no | Flush a batch after this many records (default `10000`). |
| `max_bytes` | no | Flush a batch once it reaches this many bytes (default `104857600`, 100 MB). The sink form takes this in MB. |
| `max_interval_seconds` | no | Flush a batch that has been open this long, even if it is small (default `60`). |

### Object name placeholders

The `object_template` is rendered once per batch, when it is flushed:

- `{pipeline_id}` — the pipeline that produced the records
- `{sink_id}` — this sink's ID
- `{date}` — UTC date of the flush (e.g. `2026-10-22`)
- `{hour}` — UTC hour of the flush, two digits (e.g. `09`)
- `{timestamp}` — UTC flush time, compact ISO-8601 (e.g. `20261022T093015Z`)
- `{uid}` — a random, unique token

Include `{uid}` or `{timestamp}` so successive batches don't overwrite each other.
The extension is added from the format: `.ndjson`, `.ndjson.gz` or `.parquet`.

Example — Hive-style daily folders:

```
object_template: events/dt={date}/hour={hour}/{uid}
```

## Formats

- **NDJSON** — one JSON object per line. With `gzip` the object is uploaded with
  `Content-Encoding: gzip`, so GCS can serve it decompressed to clients that
  ask for that (decompressive transcoding).
- **Parquet** — columnar, typed. The schema is inferred from the records in the
  batch and widened as needed (an integer column that later sees a float becomes a
  float, and conflicting types fall back to string). Nested maps and lists are
  stored as JSON strings. Compression applies inside the Parquet file.

## Batching

Records are held in memory per sink and per pipeline, and written as a single object
when the first of these happens:

- the batch reaches `max_records`,
- the batch reaches `max_bytes`,
- the batch has been open for `max_interval_seconds`,
- the pipeline or Flux shuts down cleanly.

Objects up to 8 MB are sent in a single request; larger ones use a **resumable
upload**, so a dropped connection or a `5xx` resumes from the last byte GCS
confirmed instead of starting over.

> **Delivery semantics.** As with every Flux sink, a record is acknowledged once it is
> handed to the sink. Records still in an open batch when the Flux process is killed
> without a clean shutdown are lost. Lower `max_interval_seconds` to shrink that
> window.

## Authentication

Provide a **service-account key** in `credentials`, or leave it blank to use
**Application Default Credentials**, in this order:

1. a key file named by `GOOGLE_APPLICATION_CREDENTIALS`,
2. the **workload identity** of the GKE pod or GCE VM Flux runs on (the metadata
   server).

Grant the identity **`storage.objects.create`** on the bucket, for example with the
**Storage Object Creator** role (`roles/storage.objectCreator`). If you overwrite
objects with a fixed `object_template`, it also needs `storage.objects.delete`
(**Storage Object User**).

### GCS sink or S3 sink?

GCS also speaks the S3 XML API, and the [S3 sink](s3.md) can write to it by setting
`endpoint` to `https://storage.googleapis.com` with **HMAC keys**. Use that if you
already manage HMAC keys and want one object per record. Use the GCS sink when you
need any of:

- service-account or **workload identity** auth (the S3 interop path accepts HMAC
  keys only),
- batched objects, NDJSON/Parquet output or compression,
- resumable uploads for large objects.

## Networking & firewall

Flux connects **out** to `storage.googleapis.com` (and `oauth2.googleapis.com` when a
service-account key is used) over **HTTPS (TCP 443)** — there is no inbound rule to
open. Flux's **egress** must be allowed to reach them:

- Allow outbound to Google's APIs on the egress firewall / NAT gateway.
- With **Private Google Access** or **VPC Service Controls**, make sure the bucket's
  project is inside the perimeter Flux runs in, or requests are refused even though
  the credentials are valid.
- With workload identity, the pod must also reach the metadata server
  (`169.254.169.254`).

Use **Test connection** on the sink form to check reachability and permissions
before saving. It asks GCS whether the identity can create objects in the bucket and
reports `access_denied` (no permission) and `bucket_not_found` (404) distinctly.
