# Kafka Connector (Source + Sink)

Kafka is a **Pro** connector available as both a **source** (consume from a
topic) and a **sink** (produce to a topic). Together they let Flux act as a
stream processor between topics: *consume → transform / detect → produce*.

> **Pro feature.** On the Community edition the Kafka source and sink are
> gated: the type appears in the UI marked *Pro* and any saved config is
> rejected with an upgrade prompt. The real adapter ships in the Flux Pro /
> Enterprise edition. Activate a license to enable it.
> See [pricing](https://flux.dev/pricing).

Kafka is **not** a Flux core queue backend — the internal/durable queue stays
RabbitMQ. A Kafka *source* ingests external topic events **onto** that internal
queue, which your pipeline then consumes; a Kafka *sink* produces processed
records back out to a topic.

## Auth matrix

Both source and sink support the same authentication modes (entitled to Pro):

| `auth_mode` | Description |
| --- | --- |
| `plaintext` | No authentication (dev / trusted networks) |
| `sasl_plain` | SASL/PLAIN (username + password) |
| `sasl_scram_256` | SASL/SCRAM-SHA-256 |
| `sasl_scram_512` | SASL/SCRAM-SHA-512 |
| `mtls` | Mutual TLS (client cert + key) — for production clusters |

SASL credentials and TLS material are stored in the source/sink config and are
masked (`[REDACTED]`) when configuration leaves the system (e.g. API reads).

## Source (consume)

A Kafka source runs a long-lived consumer that joins a consumer group, commits
offsets, and publishes each message onto the internal queue named for the
source. A pipeline is fed by consuming that queue.

### Source configuration

| Field | Required | Description |
| --- | --- | --- |
| `bootstrap_servers` | yes | Comma-separated brokers, e.g. `broker1:9092,broker2:9092` |
| `topic` | yes | Topic to consume |
| `consumer_group` | yes | Consumer group id (drives offset management & rebalance) |
| `auth_mode` | no | One of the auth modes above (default `plaintext`) |
| `sasl_username` / `sasl_password` | conditional | Required for `sasl_*` modes |

### Source example

```json
{
  "type": "kafka",
  "bootstrap_servers": "broker1:9092,broker2:9092",
  "topic": "orders",
  "consumer_group": "flux-orders",
  "auth_mode": "sasl_scram_256",
  "sasl_username": "flux",
  "sasl_password": "s3cret"
}
```

The source survives broker restarts: it reconnects and resumes from the last
committed offset, and handles consumer-group rebalances without message loss.

## Sink (produce)

A Kafka sink produces processed records to a topic. It supports idempotent
produce by default and optional transactional (exactly-once) writes, with
configurable compression.

### Sink configuration

| Field | Required | Description |
| --- | --- | --- |
| `bootstrap_servers` | yes | Comma-separated brokers |
| `topic` | yes | Destination topic |
| `auth_mode` | no | One of the auth modes above (default `plaintext`) |
| `compression` | no | `none` (default), `snappy`, `zstd`, or `lz4` |
| `transactional` | no | `true` for exactly-once (transactional) produce; default `false` (idempotent) |

### Sink example

```json
{
  "type": "kafka",
  "bootstrap_servers": "broker1:9092,broker2:9092",
  "topic": "orders.enriched",
  "auth_mode": "mtls",
  "compression": "zstd",
  "transactional": true
}
```

Ordering is preserved within a partition. Transactional produce trades some
throughput for exactly-once delivery; idempotent produce (the default) prevents
duplicates on retry without the transactional overhead.

## Networking & firewall

Flux **dials out** to your Kafka brokers — for both producing (sink) and
consuming (source). A connector can save with valid credentials and still fail
to deliver or ingest if the network path to the cluster is blocked, so get the
networking right before attaching it to a pipeline. Use **Test connection** on
the source/sink form to verify reachability and auth up front.

The egress/allowlisting model is the same as for
[external databases](external-databases.md): your broker's firewall sees the
connection arriving from the **Flux server's egress IP** — in cloud deployments
usually a **NAT gateway's Elastic/static IP**, not Flux's private IP — and that
is the address to allowlist (on the broker security groups and on any VPC
peering / PrivateLink / VPN route between the two networks). See that page for
how to find the egress IP and how to handle multiple Flux nodes/subnets.

Two things are specific to Kafka and catch people out:

- **Allowlist every broker, not just the bootstrap server.** `bootstrap_servers`
  is only the entry point: the client fetches cluster metadata and then connects
  **directly to the broker that leads each partition**. Your firewall rules must
  cover **all** brokers in the cluster and their Kafka ports (commonly `9092`,
  or `9093` for TLS) — not only the host(s) listed in `bootstrap_servers`.
- **Advertised listeners must be reachable.** A broker answers metadata with the
  host/port set as its *advertised listener*, and the client reconnects to
  **that** address. If a broker advertises an internal/private hostname that the
  Flux server can't resolve or route to, the bootstrap connection succeeds but
  produce/consume then times out. Make sure the cluster advertises addresses
  reachable from Flux's egress — this is the usual cause of "connects, then
  hangs" with managed or dockerized Kafka.
