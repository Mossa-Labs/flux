# Amazon SQS Connector (Source)

Amazon SQS is a **Pro** connector available as a **source** — it receives messages
from an SQS queue and lands each one onto Flux's internal queue, which your
pipeline then consumes. It opens the AWS event-driven path: *SQS message →
transform / detect → sink*.

> **Pro feature.** On the Community edition the SQS source is gated: the type
> appears in the UI marked *Pro* and any saved config is rejected with an upgrade
> prompt. The real adapter ships in the Flux Pro / Enterprise edition. Activate a
> license to enable it. See [pricing](https://fluxdata.tech/pricing).

SQS is **not** a Flux core queue backend — the internal/durable queue stays
RabbitMQ. An SQS *source* ingests external queue messages **onto** that internal
queue, which your pipeline consumes.

## Auth matrix

| `auth_mode` | Description |
| --- | --- |
| `iam_role` (default) | Ambient IAM role from EC2/ECS/EKS instance metadata — no stored secrets |
| `static` | Static `access_key_id` + `secret_access_key` (optional `session_token`) |
| `sso` | AWS IAM Identity Center (SSO) profile |
| `assume_role` | Assume a `role_arn` (cross-account), optionally with an `external_id` |

Static credentials are stored in the source config and are masked (`[REDACTED]`)
when configuration leaves the system (e.g. API reads). Prefer `iam_role` or
`assume_role` in AWS-hosted deployments so no long-lived secrets are stored.

## Source configuration

| Field | Required | Description |
| --- | --- | --- |
| `queue_url` | yes | Full SQS queue URL (e.g. `https://sqs.us-east-1.amazonaws.com/123456789012/my-queue`) |
| `region` | yes | AWS region the queue lives in (e.g. `us-east-1`) |
| `auth_mode` | no | One of the auth modes above (default `iam_role`) |
| `access_key_id` / `secret_access_key` | conditional | Required for `static`; optional `session_token` |
| `role_arn` | conditional | Required for `assume_role`; optional `external_id` |
| `wait_time_seconds` | no | Long-polling wait per receive call, `0`–`20` (default `20`) |
| `max_number_of_messages` | no | Messages received per batch, `1`–`10` (default `10`) |
| `visibility_timeout` | no | Seconds a received message stays invisible before redelivery |

### Standard vs FIFO queues

Both **standard** and **FIFO** (`.fifo` suffix) queues are supported. FIFO queues
preserve ordering within a **message group** (`MessageGroupId`) and use
`MessageDeduplicationId` for exactly-once delivery within the dedup window; Flux
consumes them per message group so group ordering is preserved end to end.

### Example

```json
{
  "type": "sqs",
  "queue_url": "https://sqs.us-east-1.amazonaws.com/123456789012/orders.fifo",
  "region": "us-east-1",
  "auth_mode": "assume_role",
  "role_arn": "arn:aws:iam::123456789012:role/flux-sqs-consumer",
  "wait_time_seconds": 20,
  "max_number_of_messages": 10,
  "visibility_timeout": 60
}
```

## Delivery semantics

- **Visibility timeout** — a received message is hidden for `visibility_timeout`
  seconds. Flux deletes (acks) a message **only after** it is safely enqueued, so
  a failure before enqueue leaves the message unacked and SQS redelivers it once
  the timeout expires. Set the timeout comfortably above your pipeline's
  per-message processing time to avoid premature redelivery.
- **Batch receive** — up to `max_number_of_messages` (10) messages arrive per
  call. Acks are per-message, so a partial-batch failure only redelivers the
  messages that were not successfully enqueued.
- **FIFO ordering** — preserved within a message group; a stuck message blocks
  only its own group, not the whole queue.
- **Long polling** — `wait_time_seconds` (up to 20) reduces empty receives and
  API cost; an idle queue simply returns no messages until one arrives.

## Networking & firewall

Flux **dials out** to the SQS regional endpoint
(`sqs.<region>.amazonaws.com`, HTTPS/443). A source can save with valid
credentials and still fail to ingest if the network path is blocked, so get the
networking right before attaching it to a pipeline. Use **Test connection** on the
source form to verify reachability and auth up front.

The egress model is the same as for
[external databases](external-databases.md): from outside a VPC, AWS sees the
connection arriving from the **Flux server's egress IP** — in cloud deployments
usually a **NAT gateway's Elastic/static IP**. Inside a VPC, prefer an **SQS
interface VPC endpoint** (PrivateLink) so traffic never leaves the AWS network;
scope the endpoint's security group and the consumer IAM policy to the specific
queue ARN.
