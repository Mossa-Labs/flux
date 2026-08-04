# RabbitMQ (External) Connector (Source)

RabbitMQ (External) is a **Pro** connector available as a **source** — it consumes
messages from a **customer's own external RabbitMQ broker** and lands each one onto
Flux's internal queue, which your pipeline then consumes: *broker → transform /
detect → sink*.

> **Not the internal RabbitMQ queue backend.** This connector is different from
> Flux's internal RabbitMQ queue adapter (the durable-queue *backend* that Flux
> uses to move events between its own stages). The external source reads from a
> **third-party broker you operate**, over its **own** connection, and never
> touches Flux's internal `flux.events*` exchanges. The two run independently and
> can be used at the same time.

> **Pro feature.** On the Community edition the RabbitMQ (External) source is
> gated: the type appears in the UI marked *Pro* and any saved config is rejected
> with an upgrade prompt. The real adapter ships in the Flux Pro / Enterprise
> edition. Activate a license to enable it. See
> [pricing](https://fluxdata.tech/pricing.html).

## Auth matrix

| `auth_mode` | Description |
| --- | --- |
| `plain` (default) | Username / password (AMQP PLAIN). Credentials stored in the source config, masked when configuration leaves the system. |
| `mtls` | X.509 mutual TLS. The broker verifies the client certificate; Flux verifies the broker against the supplied CA. No username/password. |
| `external` | SASL `EXTERNAL` — the broker derives the identity from the presented client certificate (e.g. the `rabbitmq_auth_mechanism_ssl` plugin, or LDAP mapping). Requires TLS client certs, same as `mtls`. |

For `mtls` and `external`, supply `ca_cert`, `client_cert`, and `client_key` as PEM.
Certificate material and passwords are stored in the source config and are masked
(`[REDACTED]`) when configuration leaves the system (e.g. API reads). Use `mtls` or
`external` with a private CA where you want to avoid storing a shared password.

## Source configuration

| Field | Required | Description |
| --- | --- | --- |
| `host` | yes | External RabbitMQ broker hostname |
| `port` | no | AMQP port (default `5672`, or `5671` for TLS) |
| `virtual_host` | no | AMQP virtual host (default `/`) |
| `queue` | yes | Queue to consume from |
| `exchange_type` | no | `none` (consume the queue directly), `direct`, `topic`, or `fanout` |
| `exchange` | conditional | Exchange name to bind the queue to; required when `exchange_type` is not `none` |
| `routing_key` | conditional | Binding key; used for `direct` / `topic` (ignored for `fanout`) |
| `auth_mode` | no | One of the auth modes above (default `plain`) |
| `username` | conditional | Broker username; required for `plain` |
| `password` | conditional | Broker password; required for `plain` |
| `ca_cert` | conditional | PEM CA bundle; required for `mtls` / `external` |
| `client_cert` | conditional | PEM client certificate; required for `mtls` / `external` |
| `client_key` | conditional | PEM client private key; required for `mtls` / `external` |
| `prefetch_count` | no | QoS: unacked messages the broker may deliver at once, 1–65535 (default 50) |
| `consumer_priority` | no | Optional `x-priority` for this consumer (higher wins) |

### Example — queue, username/password

```json
{
  "type": "rabbitmq_external",
  "host": "rabbit.example.com",
  "port": 5672,
  "virtual_host": "/",
  "queue": "orders",
  "auth_mode": "plain",
  "username": "flux",
  "password": "s3cret",
  "prefetch_count": 50
}
```

### Example — topic exchange with mTLS

```json
{
  "type": "rabbitmq_external",
  "host": "rabbit.example.com",
  "port": 5671,
  "queue": "orders",
  "exchange_type": "topic",
  "exchange": "events",
  "routing_key": "orders.#",
  "auth_mode": "mtls",
  "ca_cert": "-----BEGIN CERTIFICATE-----\n...",
  "client_cert": "-----BEGIN CERTIFICATE-----\n...",
  "client_key": "-----BEGIN PRIVATE KEY-----\n..."
}
```

## Exchanges & bindings

- **`none`** — Flux consumes the named `queue` directly. Use this when the queue
  already exists and is bound however you like on the broker.
- **`direct`** — the queue is bound to a direct exchange on an exact `routing_key`.
- **`topic`** — the queue is bound to a topic exchange with a pattern `routing_key`
  (e.g. `orders.#`).
- **`fanout`** — the queue is bound to a fanout exchange; every message is
  delivered regardless of routing key (`routing_key` is ignored).

## Prefetch, QoS & ordering

`prefetch_count` sets the AMQP QoS prefetch — the number of unacknowledged
messages the broker will deliver before waiting for acks. Higher values improve
throughput at the cost of more in-flight work; lower values give tighter
back-pressure. Flux acks a message only **after** it is safely enqueued onto the
internal queue.

## Delivery semantics

- **At-least-once.** A message is acked only **after** it is enqueued onto the
  internal queue, so a crash between publish and ack causes the broker to
  redeliver — a redelivered message can appear twice downstream. For
  exactly-once effects use an idempotent downstream (e.g. a sink keyed on a
  stable message id).
- **Requeue on failure.** If the publish to the internal queue fails, the message
  is rejected and requeued on the broker so it is retried rather than lost.
- **Dead-lettering.** Configure a dead-letter exchange (DLX) on the broker side
  for messages that repeatedly fail; Flux honours the broker's DLX policy on
  rejected messages.

## Networking & firewall

Flux **dials out** to the external broker (AMQP `5672`, or AMQPS `5671` for TLS).
A source can save with valid credentials and still fail to ingest if the network
path is blocked, so get the networking right before attaching it to a pipeline.
Use **Test connection** on the source form to verify reachability and auth up
front.

From outside your network, the broker sees the connection arriving from the
**Flux server's egress IP** — usually a **NAT gateway's static IP**. Allow that IP
through the broker's firewall / security group, and for `mtls` / `external` ensure
the broker trusts the CA that issued the client certificate.
