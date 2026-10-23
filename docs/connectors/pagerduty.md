# PagerDuty Connector (Sink)

PagerDuty is an **Enterprise** connector available as a **sink** — it turns
processed records into PagerDuty incidents through the
[Events API v2](https://developer.pagerduty.com/docs/events-api-v2/overview/).
It routes critical anomalies straight to on-call: *ingest → transform / detect →
page PagerDuty*, and closes the incident again when the data says it's resolved.

> **Enterprise feature.** On the Community and Pro editions the PagerDuty sink is
> gated: the type appears in the UI under *Flux Enterprise* and any saved config is
> rejected with an upgrade prompt. The real adapter ships in the Flux Enterprise
> edition. Activate a license to enable it. See
> [pricing](https://fluxdata.tech/pricing.html).

A PagerDuty *sink* egresses processed records **out** of a pipeline. Each record
becomes exactly one event — `trigger`, `acknowledge` or `resolve`. PagerDuty has
no batch endpoint, so there is no batching.

The same license also enables a [PagerDuty alert channel](#pagerduty-as-an-alert-channel)
for alert rules.

## Setting up the integration key

1. In PagerDuty, open the service that should receive Flux incidents (or create
   one) and go to **Integrations → Add an integration**.
2. Choose **Events API v2** and copy the **Integration Key** (32 characters).
3. Paste it into the sink's **Integration Key** field. If your PagerDuty account
   is hosted in the EU, set **Service Region = EU**.

The integration key is a secret: it is encrypted at rest, masked (`[REDACTED]`)
whenever configuration leaves the system (e.g. API reads), never pre-filled when
editing (leave it blank to keep the stored key), and never written to logs —
failures log only its first four characters.

## Configuration

| Field | Required | Description |
| --- | --- | --- |
| `routing_key` | yes | Events API v2 integration key (32 characters). Secret. |
| `region` | no | `us` (default, `events.pagerduty.com`) or `eu` (`events.eu.pagerduty.com`). |
| `event_action` | no | `trigger` (default), `acknowledge` or `resolve` — the action for every record. |
| `action_field` | no | Record field (dot-paths supported) holding the action. Overrides `event_action` per record. |
| `dedup_key_template` | when acknowledging/resolving | Template for the dedup key that ties events to one incident. Required when `event_action` is `acknowledge`/`resolve` or `action_field` is set. |
| `summary_template` | no | Incident title. Defaults to `Flux alert from pipeline <id>`. |
| `severity` | no | Default severity: `critical`, `error` (default), `warning` or `info`. |
| `severity_field` | no | Record field holding a severity to map (see [Severity](#severity)). |
| `severity_map` | no | JSON object mapping your severity values to PagerDuty's. |
| `source` | no | The affected system. Defaults to `flux`. |
| `component`, `group`, `class` | no | Optional PagerDuty classification fields. |
| `custom_details_template` | no | JSON object shown on the incident. Defaults to the whole record. |
| `client`, `client_url` | no | Label and link back to Flux on the incident (`client` defaults to `Flux`). |

Every template field interpolates `{field}` placeholders from the record
(dot-paths supported, e.g. `{payload.host}`), plus `{pipeline_id}` and
`{sink_id}`, which always name the delivering pipeline and sink. A placeholder
with no value renders as an empty string. Summary and the classification fields
render on a single line; the summary is truncated to 1024 characters and the
dedup key to 255.

## Event actions and dedup keys

PagerDuty groups events into incidents by **dedup key**:

- A `trigger` with a dedup key that matches an **open** incident updates that
  incident instead of opening a duplicate. Without a dedup key, PagerDuty
  generates one and every trigger opens a new incident.
- `acknowledge` and `resolve` find the incident by dedup key, so they need one.
  A record whose dedup key renders empty is rejected before anything is sent.

To open and close incidents from a single sink, set an **action field** and a
dedup key that is stable for the condition. For example, an anomaly detector
that emits `{"anomaly_type": "latency", "status": "trigger"}` while the anomaly
lasts and `{"anomaly_type": "latency", "status": "resolve"}` once it clears:

| Setting | Value |
| --- | --- |
| Action Field | `status` |
| Dedup Key Template | `{pipeline_id}-{anomaly_type}` |

A record whose action field is missing or holds anything other than
`trigger` / `acknowledge` / `resolve` uses the sink's **Event Action**.

## Severity

With a **severity field** set, its value is mapped to a PagerDuty severity in
this order:

1. The sink's **severity mapping** (JSON object, matched case-insensitively),
   e.g. `{"sev1": "critical", "sev2": "error", "sev3": "warning"}`.
2. The built-in table below (case-insensitive, surrounding spaces ignored).
3. Otherwise the **default severity** (`error` unless changed).

| Record value | PagerDuty severity |
| --- | --- |
| `critical`, `crit`, `fatal`, `emergency`, `emerg`, `p1` | `critical` |
| `error`, `err`, `high`, `p2` | `error` |
| `warning`, `warn`, `medium`, `p3` | `warning` |
| `info`, `low`, `notice`, `debug`, `p4`, `p5` | `info` |

Without a severity field every trigger uses the default severity.

## Custom details

By default the whole record is attached to the incident as its custom details.
To show a curated set instead, set **Custom Details** to a JSON object; its string
values are interpolated:

```json
{"metric": "{metric}", "value": "{value}", "host": "{payload.host}"}
```

## Testing the connection

**Test Connection** on the Sinks list sends a `resolve` for a random dedup key that no incident
uses. It confirms the key is well-formed and accepted by the Events API without
opening or closing anything, so nobody is paged. PagerDuty may accept events for
a well-formed key that doesn't belong to a service, so send a real trigger to
confirm routing end to end.

## Rate limits & delivery

PagerDuty rate-limits the Events API per integration key. The sink honors
PagerDuty's `Retry-After` header on `429` responses and retries transient `5xx`
failures and network errors with exponential backoff (3 attempts by default;
`max_attempts`, `retry_delay_ms` and `timeout_ms` tune this). A `400` (invalid
event) fails immediately with PagerDuty's error message. With a dedup key, a
retried trigger is idempotent.

High-volume pipelines should aggregate or filter upstream — one record is one
event, and paging on every record is rarely what on-call wants.

## Networking / egress

Outbound HTTPS (TCP 443) to `events.pagerduty.com` (US) or
`events.eu.pagerduty.com` (EU). The Flux node's egress / NAT and any firewall
allowlist must permit that host, or delivery fails despite a valid key.

## PagerDuty as an alert channel

With the same Enterprise license, alert rules on **Alerts** can page PagerDuty
alongside email, webhook and Slack. Paste the service's integration key into
**PagerDuty integration key** and choose a severity.

- Each firing triggers an incident whose dedup key is unique to the rule, so a
  rule that keeps firing updates its open incident instead of opening new ones.
  The rule's cooldown still applies.
- The incident summary names the rule and trigger; the trigger data is attached
  as custom details.
- The key is write-only: it is never shown again after saving. Leave the field
  blank when editing to keep it, or tick **Remove the PagerDuty channel**.
- **Test** checks the key the same non-paging way as the sink's connection test.
