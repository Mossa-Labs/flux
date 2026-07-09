# Amazon Kinesis Connector (Source)

Amazon Kinesis Data Streams is a **Pro** connector available as a **source** — it
consumes records from a Kinesis stream's shards and lands each one onto Flux's
internal queue, which your pipeline then consumes. It covers the high-throughput
AWS streaming path where SQS doesn't fit: *stream → transform / detect → sink*.

> **Pro feature.** On the Community edition the Kinesis source is gated: the type
> appears in the UI marked *Pro* and any saved config is rejected with an upgrade
> prompt. The real adapter ships in the Flux Pro / Enterprise edition. Activate a
> license to enable it. See [pricing](https://fluxdata.tech/pricing).

Kinesis is **not** a Flux core queue backend — the internal/durable queue stays
RabbitMQ. A Kinesis *source* ingests external stream records **onto** that
internal queue, which your pipeline consumes.

## Auth matrix

| `auth_mode` | Description |
| --- | --- |
| `iam_role` (default) | Ambient IAM role from EC2/ECS/EKS instance metadata — no stored secrets |
| `static` | Static `access_key_id` + `secret_access_key` (optional `session_token`) |

Static credentials are stored in the source config and are masked (`[REDACTED]`)
when configuration leaves the system (e.g. API reads). Prefer `iam_role` in
AWS-hosted deployments so no long-lived secrets are stored. (SSO and
cross-account assume-role are on the roadmap.)

## Source configuration

| Field | Required | Description |
| --- | --- | --- |
| `stream_name` | yes* | Kinesis data stream name (*or* provide `stream_arn`) |
| `stream_arn` | yes* | Full stream ARN (alternative to `stream_name`, e.g. cross-account) |
| `region` | yes | AWS region the stream lives in (e.g. `us-east-1`) |
| `auth_mode` | no | One of the auth modes above (default `iam_role`) |
| `access_key_id` / `secret_access_key` | conditional | Required for `static`; optional `session_token` |
| `starting_position` | no | `LATEST` (default), `TRIM_HORIZON`, or `AT_TIMESTAMP` |
| `at_timestamp` | conditional | ISO-8601 timestamp; required when `starting_position` is `AT_TIMESTAMP` |

\* Provide exactly one of `stream_name` or `stream_arn`.

### Starting positions

The starting position applies only to a shard with **no saved checkpoint**; once
Flux has checkpointed a shard it always resumes from the last committed record.

- `LATEST` — only records written after the consumer starts.
- `TRIM_HORIZON` — the oldest record still retained in the stream.
- `AT_TIMESTAMP` — the first record at or after `at_timestamp`.

### Example

```json
{
  "type": "kinesis",
  "stream_name": "orders",
  "region": "us-east-1",
  "auth_mode": "iam_role",
  "starting_position": "TRIM_HORIZON"
}
```

## Delivery & checkpointing

- **Parallelism = shard count.** Flux runs one consumer per open shard, so
  throughput scales with the stream's shard count.
- **Checkpoints in Postgres.** Each shard's last successfully-published sequence
  number is committed to Flux's database, so a restart or failover resumes
  exactly where it left off — no reliance on a DynamoDB lease table.
- **At-least-once.** A record's checkpoint is written only **after** it is safely
  enqueued, so a crash between publish and checkpoint replays the record. True
  exactly-once requires an idempotent downstream (e.g. a sink keyed on the
  record's partition key + sequence number).
- **Resharding.** Shard splits and merges are handled automatically: a parent
  shard is fully drained before its children begin, so no records are lost or
  reordered across a reshard.

## Networking & firewall

Flux **dials out** to the Kinesis regional endpoint
(`kinesis.<region>.amazonaws.com`, HTTPS/443). A source can save with valid
credentials and still fail to ingest if the network path is blocked, so get the
networking right before attaching it to a pipeline. Use **Test connection** on the
source form to verify reachability and auth up front.

The egress model is the same as for
[external databases](external-databases.md): from outside a VPC, AWS sees the
connection arriving from the **Flux server's egress IP** — usually a **NAT
gateway's Elastic/static IP**. Inside a VPC, prefer a **Kinesis interface VPC
endpoint** (PrivateLink) so traffic never leaves the AWS network; scope the
endpoint's security group and the consumer IAM policy to the specific stream ARN.
