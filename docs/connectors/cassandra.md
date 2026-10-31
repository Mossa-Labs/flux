# Apache Cassandra Connector (Sink)

Apache Cassandra is a **Pro** connector available as a **sink** — it writes each
processed record as a row into a Cassandra table. It fits time-series and
high-volume IoT workloads: *ingest → transform / detect → write to Cassandra*,
with a tunable write consistency and optional TTL expiry. The same sink works
against **ScyllaDB** and **Amazon Keyspaces**, which speak the Cassandra protocol.

> **Pro feature.** On the Community edition the Cassandra sink is gated: the type
> appears in the UI marked *Pro* and any saved config is rejected with an upgrade
> prompt. The real adapter ships in the Flux Pro / Enterprise edition. Activate a
> license to enable it. See [pricing](https://fluxdata.tech/pricing.html).

## Auth matrix

| `auth_mode` | Description |
| --- | --- |
| `none` (default) | No authentication — for clusters running `AllowAllAuthenticator` |
| `password` | `username` + `password` (`PasswordAuthenticator`). Also covers LDAP-backed clusters and Amazon Keyspaces service-specific credentials |
| `sigv4` | AWS Signature Version 4, for Amazon Keyspaces with IAM credentials |

For `sigv4`, `aws_auth_mode` picks where the AWS credentials come from:

| `aws_auth_mode` | Description |
| --- | --- |
| `iam_role` (default) | Ambient IAM role from EC2/ECS/EKS instance metadata — no stored secrets |
| `static` | Static `access_key_id` + `secret_access_key` (optional `session_token`) |
| `assume_role` | Assume a `role_arn` (cross-account), optionally with an `external_id` |

**Mutual TLS** is independent of the auth mode: turn on `tls` and set
`tls_cert_file` / `tls_key_file` to present a client certificate, on its own or
alongside password auth.

`password`, `secret_access_key` and `session_token` are encrypted at rest and
masked (`[REDACTED]`) when configuration leaves the system (e.g. API reads).

When editing a sink, leave the secrets blank to keep the stored ones. Switching
away from `password` auth removes the stored username and password; switching
away from SigV4 with static keys removes the stored keys and session token.
Entering a new `secret_access_key` without a new `session_token` also removes the
stored token, since a token is only valid with the key pair it was issued for.

## Sink configuration

| Field | Required | Description |
| --- | --- | --- |
| `contact_points` | yes | Comma-separated hosts used to discover the cluster; a host may carry its own `:port` |
| `port` | no | Native protocol port for hosts without one (default `9042`) |
| `local_datacenter` | no | Datacenter to route writes to; recommended for multi-datacenter clusters |
| `keyspace` | yes | Keyspace of the target table |
| `table` | yes | Target table |
| `consistency` | no | Write consistency: `one`, `local_one`, `quorum`, `local_quorum` (default) or `all` |
| `auth_mode` | no | One of the auth modes above (default `none`) |
| `username` / `password` | conditional | Required for `password` |
| `region` | conditional | AWS region; required for `sigv4` |
| `aws_auth_mode` | no | Credential source for `sigv4` (default `iam_role`) |
| `access_key_id` / `secret_access_key` | conditional | Required for `aws_auth_mode: static`; optional `session_token` |
| `role_arn` | conditional | Required for `aws_auth_mode: assume_role`; optional `external_id` |
| `tls` | no | Encrypt the connection (default `false`) |
| `tls_ca_file` | no | CA bundle path; without it the system trust store is used |
| `tls_cert_file` / `tls_key_file` | no | Client certificate and key paths, for mutual TLS |
| `ttl_seconds` | no | Expire written rows after this many seconds (`USING TTL`) |
| `timeout_ms` | no | Per-write timeout in milliseconds |

Certificate paths are read on the Flux server, so the files must exist there (for
example, mounted from a secret).

### Example — Amazon Keyspaces with an IAM role

```json
{
  "type": "cassandra",
  "contact_points": "cassandra.eu-west-1.amazonaws.com",
  "port": 9142,
  "keyspace": "telemetry",
  "table": "readings",
  "consistency": "local_quorum",
  "auth_mode": "sigv4",
  "region": "eu-west-1",
  "aws_auth_mode": "iam_role",
  "tls": true
}
```

## Data mapping

Each record is written to the columns of the same name; record fields with no
matching column are ignored. A column the record leaves out keeps its stored
value: Flux leaves it unset rather than writing a null, so no tombstone is
created. An explicit `null` in the record does write a null.

Flux prepares one `INSERT` statement for the table and reuses it for every
record. It re-reads the table's schema every 30 seconds, so a column added with
`ALTER TABLE` starts receiving values within 30 seconds (or right away after
**Test connection**). A dropped column is handled on the next write.

Every record must carry the table's **partition key** and **clustering key**
columns. A record missing one is rejected rather than written.

Values are converted to each column's CQL type:

| CQL type | Accepted record values |
| --- | --- |
| `text`, `varchar`, `ascii` | strings |
| `int`, `bigint`, `smallint`, `tinyint`, `varint` | integers, or numeric strings |
| `float`, `double`, `decimal` | numbers, or numeric strings |
| `boolean` | `true` / `false` |
| `timestamp` | ISO 8601 strings, or epoch milliseconds |
| `date` | `YYYY-MM-DD` strings |
| `uuid`, `timeuuid` | canonical UUID strings |
| `blob` | Base64 strings |
| `list`, `set`, `map` | JSON arrays and objects, with each element converted the same way |

Counter tables are not supported, because counters can only be incremented, not
inserted.

## Consistency

`consistency` sets how many replicas must acknowledge each write before it counts
as delivered. `local_quorum` (the default) keeps writes durable while staying
inside the local datacenter. `quorum` and `all` wait on remote datacenters too,
and fail when too few replicas are reachable; `one` and `local_one` are the
fastest and the least durable.

Amazon Keyspaces accepts only `local_quorum` for writes.

## TTL expiry (optional)

Set `ttl_seconds` to write every row `USING TTL`: Cassandra deletes the row once
the TTL elapses. A table-level `default_time_to_live` applies when `ttl_seconds`
is not set.

## Best practices

- **Design the partition key for the write pattern.** Rows with the same partition
  key live on the same replicas. For time series, bucket the partition by device
  *and* time (for example `(device_id, day)`) so no partition grows without bound
  and writes spread across the cluster.
- **Avoid large unlogged batches.** A batch spanning many partitions makes one
  coordinator node do the work of many, which is slower than independent writes.
  Flux writes each record as its own prepared `INSERT` for this reason.
- **Use logged batches only for atomicity.** A logged batch guarantees that all or
  none of its statements apply, at the cost of an extra write to the batch log.
  It is not a throughput optimization.
- **Match consistency to the replication factor.** With a replication factor of 3,
  `local_quorum` tolerates one replica down per datacenter; `all` tolerates none.

## Compatibility

| Database | Notes |
| --- | --- |
| Apache Cassandra 3.11 and later | Tested against Cassandra 4.1 |
| ScyllaDB | Drop-in; use `password` auth if the cluster enforces it |
| Amazon Keyspaces | Port `9142` with `tls` on; `sigv4` or `password` (service-specific credentials); writes must use `local_quorum` |

For Keyspaces with `sigv4`, the IAM principal Flux runs as (or the assumed role)
needs `cassandra:Modify` on the table, to write, and `cassandra:Select` on the
`system*` keyspaces, to read the table schema.

## Networking & firewall

Flux **dials out** to every node in the cluster on the native protocol port
(`9042` by default, or `9142` for TLS on Amazon Keyspaces). The contact points are
only used to discover the cluster, so the Flux server must be able to reach the
address each node advertises, not just the contact points. A sink can save and
still fail to write if the network path is blocked, so use **Test connection** on
the sink form to verify reachability, auth, and that the keyspace and table exist.

The egress model is the same as for
[external databases](external-databases.md): the cluster sees the connection
arriving from the **Flux server's egress IP**. Allow that address in the cluster's
firewall or security group. For Amazon Keyspaces inside a VPC, prefer an
**interface VPC endpoint** so traffic never leaves the AWS network.
