# MongoDB Connector (Sink)

MongoDB is a **Pro** connector available as a **sink** — it writes each processed
record as a document into a MongoDB collection. It fits the streaming/AI path as a
flexible document landing zone: *ingest → transform / detect → write to MongoDB*,
with optional upserts and TTL expiry.

> **Pro feature.** On the Community edition the MongoDB sink is gated: the type
> appears in the UI marked *Pro* and any saved config is rejected with an upgrade
> prompt. The real adapter ships in the Flux Pro / Enterprise edition. Activate a
> license to enable it. See [pricing](https://fluxdata.tech/pricing).

MongoDB is **not** a Flux core queue backend — the internal/durable queue stays
RabbitMQ. A MongoDB *sink* egresses processed records **out** of a pipeline to an
external MongoDB deployment (self-hosted or Atlas).

## Connection

Provide **either** a connection URI (recommended — covers Atlas, replica sets,
auth and TLS in one string) **or** discrete host/port fields.

| Field | Required | Description |
| --- | --- | --- |
| `uri` | one-of | `mongodb://…` or `mongodb+srv://…` connection string. Takes precedence when set. |
| `host` / `port` | one-of | Used when no `uri` (port default `27017`) |
| `database` | yes | Target database (required unless embedded in the `uri`) |
| `collection` | yes | Target collection |

The `uri` may embed credentials and is masked (`[REDACTED]`) when configuration
leaves the system (e.g. API reads).

## Auth matrix

| `auth_mode` | Description |
| --- | --- |
| `none` | No authentication (dev / trusted networks) |
| `scram` | SCRAM-SHA-256 — `username` + `password` (+ optional `auth_source`, usually `admin`) |
| `x509` | X.509 client-certificate auth (mTLS) — `tls_cert_file` + `tls_key_file` (+ `tls_ca_file`) |

Set `tls: true` to connect over TLS. `password` is stored in the sink config and
is masked when configuration leaves the system. For **Atlas**, use a
`mongodb+srv://` URI — the driver resolves the DNS seedlist and connects over TLS.

## Write modes

| `write_mode` | Behaviour |
| --- | --- |
| `insert` (default) | Inserts each record as a new document (`insertOne` / batched `insertMany`) |
| `upsert` | Matches on `upsert_keys` and updates-or-inserts (`updateOne` with `upsert: true`) |

- **`upsert_keys`** — comma-separated field names forming the match filter (e.g.
  `_id`, or `user_id,day`). Required for `upsert` mode.
- **`_id` preservation** — if a record contains an `_id`, it is used as-is;
  otherwise MongoDB generates an ObjectId.

## TTL expiry (optional)

Set both `ttl_field` and `ttl_seconds` to have Flux create a **TTL index** on the
collection (`expireAfterSeconds`), so MongoDB automatically deletes documents
`ttl_seconds` after the value in `ttl_field`. The field must hold a
date/timestamp. The index is created once when the connection is established.

## Sink configuration

| Field | Required | Description |
| --- | --- | --- |
| `uri` **or** `host`/`port` | yes | Connection (see above) |
| `database` | yes | Database name |
| `collection` | yes | Collection name |
| `auth_mode` | no | `none` / `scram` / `x509` (default `none`) |
| `username` / `password` / `auth_source` | conditional | Required for `scram` |
| `tls` | no | Connect over TLS |
| `tls_ca_file` / `tls_cert_file` / `tls_key_file` | conditional | TLS/X.509 material (paths on the Flux host) |
| `write_mode` | no | `insert` (default) / `upsert` |
| `upsert_keys` | conditional | Comma-separated match fields; required for `upsert` |
| `ttl_field` / `ttl_seconds` | no | Optional TTL index |

### Example — Atlas upsert

```json
{
  "type": "mongodb",
  "uri": "mongodb+srv://flux:s3cret@cluster0.abcde.mongodb.net",
  "database": "events",
  "collection": "scores",
  "write_mode": "upsert",
  "upsert_keys": "user_id,day",
  "ttl_field": "created_at",
  "ttl_seconds": 2592000
}
```

### Example — self-hosted SCRAM insert

```json
{
  "type": "mongodb",
  "host": "mongo.internal",
  "port": 27017,
  "database": "events",
  "collection": "raw",
  "auth_mode": "scram",
  "username": "flux",
  "password": "s3cret",
  "auth_source": "admin",
  "tls": true
}
```

## Networking & firewall

Flux **dials out** to the MongoDB deployment (`host:port`, or the hosts resolved
from a `mongodb+srv` seedlist). A sink can save with valid credentials and still
fail to write if the network path is blocked, so get the networking right before
attaching it to a pipeline. Use **Test connection** on the sink form to verify
reachability and auth up front.

The egress model is the same as for
[external databases](external-databases.md): the deployment sees the connection
arriving from the **Flux server's egress IP** — in cloud deployments usually a
**NAT gateway's Elastic/static IP**. For Atlas, add that IP to the project's
**IP Access List**. For a replica set, the Flux node must reach **every** member's
advertised host:port, not just the seed.
