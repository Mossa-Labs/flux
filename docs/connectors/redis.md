# Redis Connector (Sink)

Redis is a **Pro** connector available as a **sink** — it writes each processed
record out to a Redis server. It fits the streaming/AI path as a fast in-memory
destination: *ingest → transform / detect → write to Redis*, e.g. publish anomaly
scores to a hash for downstream services to look up, append events to a list, or
push onto a stream for other consumers.

> **Pro feature.** On the Community edition the Redis sink is gated: the type
> appears in the UI marked *Pro* and any saved config is rejected with an upgrade
> prompt. The real adapter ships in the Flux Pro / Enterprise edition. Activate a
> license to enable it. See [pricing](https://fluxdata.tech/pricing.html).

Redis is **not** a Flux core queue backend — the internal/durable queue stays
RabbitMQ. A Redis *sink* egresses processed records **out** of a pipeline to an
external Redis server.

## Value shapes

Each record is written using the configured `value_shape`. The record map is
JSON-encoded where a single value is stored; hash/stream shapes map the record's
fields onto Redis fields.

| `value_shape` | Redis command | Behaviour |
| --- | --- | --- |
| `string` | `SET` | Stores the JSON-encoded record at the templated key |
| `hash` | `HSET` | Writes the record's fields as hash fields at the templated key |
| `list` | `RPUSH` | Appends the JSON-encoded record to the list at the templated key |
| `stream` | `XADD` | Appends the record's fields as a stream entry at the templated key |

## Key template

`key_template` builds the target key per record, using the same placeholders as
the S3 sink:

| Placeholder | Expands to |
| --- | --- |
| `{id}` | The record's `id` (or a generated message id) |
| `{timestamp}` | Delivery timestamp (Unix seconds) |
| `{date}` | Delivery date (`YYYY-MM-DD`) |
| `{pipeline_id}` | The pipeline the record flowed through |

Example: `scores:{id}` → `scores:abc123`.

## TTL

`ttl_seconds` sets a per-key expiry (via `SET ... EX` or `EXPIRE`). Leave it blank
for no expiry. TTL is **ignored for the `stream` shape** (streams are trimmed by
length/age, not per-key expiry).

## Auth matrix

| `auth_mode` | Description |
| --- | --- |
| `none` (default) | No authentication (dev / trusted networks) |
| `password` | Legacy `requirepass` — password only (`AUTH <password>`) |
| `acl` | Redis 6+ ACL — `username` + `password` (`AUTH <username> <password>`) |

Set `tls: true` to connect over TLS. The `password` is stored in the sink config
and is masked (`[REDACTED]`) when configuration leaves the system (e.g. API
reads); prefer ACL users scoped to the minimum key patterns and commands the sink
needs.

## Sink configuration

| Field | Required | Description |
| --- | --- | --- |
| `host` | yes | Redis host (e.g. `redis.internal`) |
| `port` | yes | Redis port (e.g. `6379`) |
| `db` | no | Logical database index (default `0`; ignored in cluster mode) |
| `value_shape` | yes | One of `string`, `hash`, `list`, `stream` (see above) |
| `key_template` | yes | Templated target key (see above) |
| `ttl_seconds` | no | Per-key expiry in seconds (ignored for `stream`) |
| `auth_mode` | no | One of the auth modes above (default `none`) |
| `username` | conditional | Required for `acl` |
| `password` | conditional | Required for `password` / `acl` |
| `tls` | no | Connect over TLS (default `false`) |
| `cluster` | no | Opt-in Redis Cluster mode (default `false`) |

### Example

```json
{
  "type": "redis",
  "host": "redis.internal",
  "port": 6379,
  "db": 0,
  "value_shape": "hash",
  "key_template": "scores:{id}",
  "ttl_seconds": 3600,
  "auth_mode": "acl",
  "username": "flux",
  "password": "s3cret",
  "tls": true
}
```

## Cluster mode

Set `cluster: true` to target a Redis Cluster. Keys are routed to the owning shard
by hash slot; use a hash tag in `key_template` (e.g. `scores:{id}` →
`{scores}:{id}`) if you need related keys to co-locate on one slot. Cluster mode
is opt-in — a single-node server needs no cluster flag.

## Networking & firewall

Flux **dials out** to the Redis server (`host:port`). A sink can save with valid
credentials and still fail to write if the network path is blocked, so get the
networking right before attaching it to a pipeline. Use **Test connection** on the
sink form to verify reachability and auth up front.

The egress model is the same as for
[external databases](external-databases.md): the server sees the connection
arriving from the **Flux server's egress IP** — in cloud deployments usually a
**NAT gateway's Elastic/static IP**. Inside a VPC, keep Redis on a private subnet
and scope its security group to the Flux egress IP. Never expose an unauthenticated
Redis server to the public internet.
