# Google Pub/Sub Connector (Source)

Google Cloud Pub/Sub is a **Pro** connector available as a **source** — it pulls
messages from a Pub/Sub subscription and lands each one onto Flux's internal
queue, which your pipeline then consumes. It is the GCP equivalent of the SQS and
Kinesis sources, for teams standardized on Google Cloud: *subscription →
transform / detect → sink*.

> **Pro feature.** On the Community edition the Pub/Sub source is gated: the type
> appears in the UI marked *Pro* and any saved config is rejected with an upgrade
> prompt. The real adapter ships in the Flux Pro / Enterprise edition. Activate a
> license to enable it. See [pricing](https://fluxdata.tech/pricing).

Pub/Sub is **not** a Flux core queue backend — the internal/durable queue stays
RabbitMQ. A Pub/Sub *source* ingests external subscription messages **onto** that
internal queue, which your pipeline consumes.

## Auth matrix

| `auth_mode` | Description |
| --- | --- |
| `adc` (default) | Application Default Credentials — the `GOOGLE_APPLICATION_CREDENTIALS` key file, else the GCE/GKE **metadata server** (Workload Identity). No stored secrets. |
| `service_account` | Inline service-account JSON key supplied in `credentials`. |

Inline `credentials` are stored in the source config and are masked
(`[REDACTED]`) when configuration leaves the system (e.g. API reads). Prefer
`adc` with **Workload Identity** on GKE so no long-lived key is stored. Tokens
are minted via OAuth and cached until expiry.

## Source configuration

| Field | Required | Description |
| --- | --- | --- |
| `project_id` | yes | GCP project that owns the subscription |
| `subscription` | yes | Pull subscription id (or a full `projects/<project>/subscriptions/<name>` path) |
| `auth_mode` | no | One of the auth modes above (default `adc`) |
| `credentials` | conditional | Service-account JSON; required for `service_account` |
| `ordering` | no | Preserve per-key order — see [Ordered delivery](#ordered-delivery) (default `false`) |
| `exactly_once` | no | Accepted; see [Delivery semantics](#delivery-semantics) (default `false`) |
| `max_number_of_messages` | no | Pull batch size, 1–1000 (default 10) |
| `max_ack_deadline_seconds` | no | Deadline (0–600s) applied when a message is nacked after a failed publish |

### Example

```json
{
  "type": "pubsub",
  "project_id": "my-gcp-project",
  "subscription": "orders-sub",
  "auth_mode": "adc",
  "ordering": false
}
```

Service-account example:

```json
{
  "type": "pubsub",
  "project_id": "my-gcp-project",
  "subscription": "orders-sub",
  "auth_mode": "service_account",
  "credentials": "{\"type\":\"service_account\", ...}"
}
```

## Ordered delivery

With `ordering` enabled, Flux routes all messages sharing an `orderingKey` to the
same processor, preserving per-key order end to end while still allowing
parallelism across keys. Ordering is only guaranteed when the **subscription
itself has message ordering enabled** in GCP — otherwise Pub/Sub may deliver a
key's messages out of order before they reach Flux.

## Ack deadlines & slow pipelines

Pub/Sub redelivers a message if it is not acked within the subscription's
**`ackDeadlineSeconds`**. Flux acks a message only **after** it is safely enqueued
onto the internal queue, so for slow pipelines set the subscription's ack deadline
high enough (up to 600s) to avoid premature redelivery. On a failed publish the
message is nacked with `max_ack_deadline_seconds` (when set) so it is redelivered
after that delay.

## Delivery semantics

- **Parallelism via pull.** Flux pulls the subscription concurrently and fans
  work across a processor pool (unpartitioned unless `ordering` is set).
- **At-least-once.** A message is acked only **after** it is enqueued, so a crash
  between publish and ack replays the message — a redelivered message can appear
  twice downstream. True exactly-once requires an idempotent downstream (e.g. a
  sink keyed on the Pub/Sub `messageId`).
- **Exactly-once.** `exactly_once` is accepted, and when the subscription is
  created in Pub/Sub's exactly-once mode GCP deduplicates server-side. Note that
  Flux's Broadway acknowledger provides at-least-once ack handling, so end-to-end
  exactly-once is **best-effort** and treated as a documented limitation rather
  than a guarantee.

## Networking & firewall

Flux **dials out** to the Pub/Sub API (`pubsub.googleapis.com`, HTTPS/443) and,
for token minting, to `oauth2.googleapis.com` / the GCE metadata server. A source
can save with valid credentials and still fail to ingest if the network path is
blocked, so get the networking right before attaching it to a pipeline. Use
**Test connection** on the source form to verify reachability and auth up front.

From outside GCP, Google sees the connection arriving from the **Flux server's
egress IP** — usually a **NAT gateway's static IP**. Inside a VPC, prefer
**Private Google Access** or a **Private Service Connect** endpoint so traffic
never leaves Google's network; scope the service account's IAM to the specific
subscription (`roles/pubsub.subscriber`).
