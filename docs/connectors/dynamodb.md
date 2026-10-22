# Amazon DynamoDB Connector (Sink)

Amazon DynamoDB is a **Pro** connector available as a **sink** — it writes each
processed record as an item into a DynamoDB table. It fits serverless and
event-driven AWS architectures: *ingest → transform / detect → write to DynamoDB*,
with optional idempotent (conditional) writes and TTL expiry.

> **Pro feature.** On the Community edition the DynamoDB sink is gated: the type
> appears in the UI marked *Pro* and any saved config is rejected with an upgrade
> prompt. The real adapter ships in the Flux Pro / Enterprise edition. Activate a
> license to enable it. See [pricing](https://fluxdata.tech/pricing.html).

## Auth matrix

| `auth_mode` | Description |
| --- | --- |
| `iam_role` (default) | Ambient IAM role from EC2/ECS/EKS instance metadata — no stored secrets |
| `static` | Static `access_key_id` + `secret_access_key` (optional `session_token`) |
| `assume_role` | Assume a `role_arn` (cross-account), optionally with an `external_id` |

`secret_access_key` and `session_token` are encrypted at rest and masked
(`[REDACTED]`) when configuration leaves the system (e.g. API reads). Prefer
`iam_role` or `assume_role` in AWS-hosted deployments so no long-lived secrets are
stored.

AWS SSO (IAM Identity Center) is an interactive, browser-based login unsuited to a
headless server, so it is not supported; use `iam_role` (or cross-account
`assume_role`) instead.

## Sink configuration

| Field | Required | Description |
| --- | --- | --- |
| `table_name` | yes | Target table |
| `partition_key` | yes | Name of the table's partition (hash) key attribute |
| `sort_key` | no | Name of the table's sort (range) key attribute, if it has one |
| `region` | no | AWS region of the table (default `us-east-1`) |
| `endpoint` | no | Custom endpoint URL, e.g. LocalStack or DynamoDB Local for testing |
| `auth_mode` | no | One of the auth modes above (default `iam_role`) |
| `access_key_id` / `secret_access_key` | conditional | Required for `static`; optional `session_token` |
| `role_arn` | conditional | Required for `assume_role`; optional `external_id` |
| `write_mode` | no | `put` (default) / `if_absent` / `if_newer` — see below |
| `version_attribute` | conditional | Numeric version attribute; required for `if_newer` |
| `ttl_attribute` / `ttl_seconds` | no | Optional TTL expiry — see below |

Every record must carry the key attribute(s). A record missing its partition key
(or its sort key, when one is configured) is rejected rather than written.

### Example — idempotent writes with TTL

```json
{
  "type": "dynamodb",
  "table_name": "events",
  "partition_key": "event_id",
  "region": "eu-west-1",
  "auth_mode": "assume_role",
  "role_arn": "arn:aws:iam::123456789012:role/flux-dynamodb-writer",
  "write_mode": "if_absent",
  "ttl_attribute": "expires_at",
  "ttl_seconds": 2592000
}
```

## Write modes

| `write_mode` | Behaviour |
| --- | --- |
| `put` (default) | Unconditional `PutItem` — the item replaces any existing item with the same key |
| `if_absent` | `PutItem` only if no item with that key exists (first write wins) |
| `if_newer` | `PutItem` only if no item exists, or the stored `version_attribute` is lower than the record's |

All three are safe to retry: a redelivered record either rewrites the same item
(`put`) or is skipped (`if_absent`, `if_newer`). A skipped write is treated as a
successful delivery, not an error, so a duplicate or out-of-order record never
overwrites newer data. Use `if_newer` when records for the same key can arrive out
of order and each carries a monotonically increasing version (a sequence number or
a millisecond timestamp).

## TTL expiry (optional)

Set both `ttl_attribute` and `ttl_seconds` to stamp every item with an expiry
time: Flux writes `ttl_attribute` as a Unix epoch number (seconds), `ttl_seconds`
after the write. DynamoDB deletes expired items only if **TTL is enabled on the
table for that attribute** (table settings → *Time to Live*). **Test connection**
reports an error when it is not.

## Capacity, throttling and retries

Both **on-demand** and **provisioned** tables are supported. When a write is
throttled (`ProvisionedThroughputExceededException`, `ThrottlingException`) or AWS
returns a 5xx, Flux retries it with exponential backoff before reporting a
delivery failure. On a provisioned table, size write capacity (or enable
auto scaling) for the pipeline's peak record rate. Sustained throttling shows up
as delivery failures in the pipeline logs.

## Authentication

The IAM principal Flux runs as (or the assumed role) needs, scoped to the table
ARN:

| Action | Used for |
| --- | --- |
| `dynamodb:PutItem` | Writing records (all write modes) |
| `dynamodb:BatchWriteItem` | Bulk writes |
| `dynamodb:DescribeTable` | **Test connection** — table status and key schema |
| `dynamodb:DescribeTimeToLive` | **Test connection** — TTL check when `ttl_attribute` is set |

For `assume_role`, the Flux principal also needs `sts:AssumeRole` on the
`role_arn`. Temporary credentials are cached and refreshed before they expire.

## Networking & firewall

Flux **dials out** to the DynamoDB regional endpoint
(`dynamodb.<region>.amazonaws.com`, HTTPS/443). A sink can save with valid
credentials and still fail to write if the network path is blocked, so get the
networking right before attaching it to a pipeline. Use **Test connection** on the
sink form to verify reachability, auth, and that the configured key attributes
match the table's key schema.

The egress model is the same as for
[external databases](external-databases.md): from outside a VPC, AWS sees the
connection arriving from the **Flux server's egress IP** — in cloud deployments
usually a **NAT gateway's Elastic/static IP**. Inside a VPC, prefer a **DynamoDB
gateway VPC endpoint** so traffic never leaves the AWS network; scope the endpoint
policy and the writer IAM policy to the specific table ARN.
