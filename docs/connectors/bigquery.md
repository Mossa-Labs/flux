# BigQuery Sink

BigQuery is a **Pro** sink that streams pipeline records into a Google BigQuery
table.

> **Pro feature.** On the Community edition the BigQuery sink is gated: the type
> appears in the UI marked *Pro* and any saved config is rejected with an upgrade
> prompt. The real adapter ships in the Flux Pro / Enterprise edition. Activate a
> license to enable it. See [pricing](https://fluxdata.tech/pricing.html).

Flux writes rows to BigQuery's streaming API over **HTTPS**, so — like the
[external-database connectors](external-databases.md) — it is an **outbound**
integration: the sink can save with valid credentials and still fail to deliver
if the network path to Google's APIs is blocked.

## Configuration

| Field | Required | Description |
| --- | --- | --- |
| `project_id` | yes | GCP project that owns the dataset |
| `dataset` | yes | BigQuery dataset id |
| `table` | yes | Destination table id (must already exist) |
| `credentials` | no | Service-account key JSON. If blank, Flux falls back to Application Default Credentials (see below) |
| `location` | no | Dataset location (e.g. `US`, `EU`) |

The destination table must already exist; rows are matched to columns by field
name, so create the table (and any partitioning / clustering) ahead of time.

## Authentication

Provide a **service-account key** in `credentials`, or leave it blank to use
**Application Default Credentials** — either a `GOOGLE_APPLICATION_CREDENTIALS`
key file, or the **workload identity** of the GCE/GKE node Flux runs on. Grant
the identity the **BigQuery Data Editor** role on the dataset.

## Networking & firewall

Flux connects **out** to Google's APIs over **HTTPS (TCP 443)**. There is no
inbound rule to open on Google's side, but Flux's **egress** must be allowed to
reach:

- `bigquery.googleapis.com` — the streaming insert endpoint, and
- `oauth2.googleapis.com` / the **GCE metadata server** (`169.254.169.254`) —
  used to mint access tokens.

In a typical cloud deployment Flux sits in a private subnet behind a **NAT
gateway**, so that is the egress path to keep open:

- Allow outbound **443** to the Google API hosts above on the egress firewall /
  network ACL / NAT gateway.
- If you run inside GCP with **VPC Service Controls** or **Private Google
  Access**, make sure BigQuery is reachable on the restricted / Private-Google
  path and that your service perimeter permits the project — otherwise requests
  are blocked even though the credentials are valid.

Use **Test connection** on the sink form to verify reachability and auth before
saving.
