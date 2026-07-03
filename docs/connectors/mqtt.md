# MQTT Connector (Source)

MQTT is a **Pro** connector available as a **source** — it subscribes to a broker
topic and lands each message onto Flux's internal queue, which your pipeline then
consumes. It opens the IoT / industrial path: *sensor data → transform / anomaly
detection → alert*.

> **Pro feature.** On the Community edition the MQTT source is gated: the type
> appears in the UI marked *Pro* and any saved config is rejected with an upgrade
> prompt. The real adapter ships in the Flux Pro / Enterprise edition. Activate a
> license to enable it. See [pricing](https://flux.dev/pricing).

MQTT is **not** a Flux core queue backend — the internal/durable queue stays
RabbitMQ. An MQTT *source* ingests external topic messages **onto** that internal
queue, which your pipeline consumes.

## Auth matrix

| `auth_mode` | Description |
| --- | --- |
| `none` (default) | Anonymous — dev / trusted networks |
| `username_password` | MQTT username + password |
| `mtls` | Mutual TLS (client cert + key) — common in industrial deployments |
| `jwt` | Bearer/JWT token in the MQTT password field — for cloud brokers |

Credentials and TLS material are stored in the source config and are masked
(`[REDACTED]`) when configuration leaves the system (e.g. API reads). Set `tls:
true` to use server-authenticated TLS with `username_password` / `jwt`; `mtls`
implies TLS.

## Source configuration

| Field | Required | Description |
| --- | --- | --- |
| `host` | yes | Broker hostname |
| `topic` | yes | Topic filter to subscribe to (wildcards allowed — see below) |
| `port` | no | Broker port (default `1883`, or `8883` with TLS/mTLS) |
| `qos` | no | Quality of Service: `0`, `1` (default) or `2` |
| `client_id` | no | MQTT client id (derived deterministically if omitted) |
| `clean_start` | no | Start a clean session (default `true`) |
| `keepalive` | no | Keep-alive seconds (default `60`) |
| `auth_mode` | no | One of the auth modes above (default `none`) |
| `username` / `password` | conditional | Required for `username_password` |
| `jwt` | conditional | Required for `jwt` mode |
| `ssl_certfile` / `ssl_keyfile` | conditional | Required for `mtls`; optional `ssl_cacertfile` |
| `will_topic` / `will_payload` / `will_qos` | no | Last-will (LWT) message |

### Topic wildcards

MQTT topic filters support wildcards:

- `+` — single level, e.g. `sensors/+/temp` matches `sensors/a/temp` and
  `sensors/b/temp` (but not `sensors/a/humidity`).
- `#` — multi-level, must be the final level, e.g. `factory/#` matches everything
  under `factory/`.

Invalid filters (a partial `+` level, or `#` not at the end) are rejected on save.

### Example

```json
{
  "type": "mqtt",
  "host": "broker.factory.internal",
  "port": 8883,
  "topic": "sensors/+/temp",
  "qos": 1,
  "auth_mode": "mtls",
  "ssl_certfile": "/etc/flux/mqtt/client.crt",
  "ssl_keyfile": "/etc/flux/mqtt/client.key",
  "ssl_cacertfile": "/etc/flux/mqtt/ca.crt"
}
```

## Delivery semantics

- **QoS 0** — fire-and-forget; no acknowledgement.
- **QoS 1** — at-least-once. Flux acknowledges (PUBACK) **only after** the message
  is safely enqueued, so a failure before enqueue leaves it unacked and the broker
  redelivers it.
- **QoS 2** — exactly-once handshake; Flux completes it (PUBCOMP) **only after**
  enqueue.

The source survives broker restarts: it reconnects and resubscribes
automatically, resuming ingestion without operator intervention.

## Networking & firewall

Flux **dials out** to your MQTT broker. A source can save with valid credentials
and still fail to ingest if the network path to the broker is blocked, so get the
networking right before attaching it to a pipeline. Use **Test connection** on the
source form to verify reachability and auth up front.

The egress/allowlisting model is the same as for
[external databases](external-databases.md): your broker's firewall sees the
connection arriving from the **Flux server's egress IP** — in cloud deployments
usually a **NAT gateway's Elastic/static IP**, not Flux's private IP — and that is
the address to allowlist (on the broker security group and on any VPC peering /
PrivateLink / VPN route between the two networks). Open the broker's MQTT port
(commonly `1883` plaintext or `8883` for TLS/mTLS).
