# PagerDuty Connector (Sink)

PagerDuty is an **Enterprise** connector available as a **sink**. It turns
processed records into PagerDuty incidents, routing critical anomalies straight
to on-call: *ingest → transform / detect → page PagerDuty*. It closes the
incident again when the data says it's resolved.

> **Enterprise feature.** On the Community and Pro editions the PagerDuty sink is
> gated: the type appears in the UI under *Flux Enterprise* and any saved config is
> rejected with an upgrade prompt. The real adapter ships in the Flux Enterprise
> edition. Activate an Enterprise license to enable it; a Pro license does not. See
> [pricing](https://fluxdata.tech/pricing.html).

A PagerDuty *sink* egresses processed records **out** of a pipeline. Each record
becomes exactly one action: `trigger`, `acknowledge` or `resolve`. PagerDuty has
no batch endpoint, so there is no batching.

The same license also enables a [PagerDuty alert channel](#pagerduty-as-an-alert-channel)
for alert rules.

## Choosing an auth mode

The sink talks to PagerDuty through one of two APIs, chosen by **Auth Mode**
(`auth_mode`):

| Auth mode | API | Credential | Use it when |
| --- | --- | --- | --- |
| `events_v2` (default) | [Events API v2](https://developer.pagerduty.com/docs/events-api-v2/overview/) | A service's integration key | You only need to trigger, acknowledge and resolve. Simplest setup. |
| `rest_api_key` | [REST API](https://developer.pagerduty.com/api-reference/) | A REST API key | You want urgency, priority, escalation policy or incident notes, or to update incidents by ID. |
| `rest_oauth` | REST API | A Scoped OAuth app (client ID and secret) | As above, with a credential scoped to incidents and services instead of a full API key. |

Sinks saved before auth modes existed use `events_v2` and behave exactly as before.

## Setting up the integration key (Events API v2)

1. In PagerDuty, open the service that should receive Flux incidents (or create
   one) and go to **Integrations → Add an integration**.
2. Choose **Events API v2** and copy the **Integration Key** (32 characters).
3. Paste it into the sink's **Integration Key** field. If your PagerDuty account
   is hosted in the EU, set **Service Region = EU**.

## Setting up REST API access

Both REST modes need the **Service ID** of the service to open incidents on (the
last part of the service's URL, e.g. `PABC123`) and a **Requester Email**:
the email of a user on the PagerDuty account. PagerDuty records that user as the
author of every change, so a dedicated "Flux" user is a good choice.

**REST API key** (`rest_api_key`)

1. In PagerDuty go to **Integrations → API Access Keys → Create New API Key**.
2. Leave **Read-only** unticked: the sink creates and updates incidents.
3. Paste the key into **REST API Key**.

**OAuth app** (`rest_oauth`)

1. In PagerDuty go to **Integrations → App Registration** and create an app
   with **Scoped OAuth**.
2. Grant the scopes `incidents.read`, `incidents.write` and `services.read`.
3. Copy the **Client ID** and **Client Secret** into the sink, and set
   **Account Subdomain** to your account's subdomain (`acme` for
   `acme.pagerduty.com`).

Flux exchanges the client ID and secret for an access token with the OAuth
client-credentials grant, caches it in memory, and requests a new one shortly
before it expires. No refresh token is involved, and nothing is written back to
the sink. The app must be registered in the same PagerDuty account it opens
incidents in. If PagerDuty rejects the client ID or secret, records fail for
30 seconds without asking again, so a misconfigured sink doesn't flood
PagerDuty with token requests.

## Secrets

The integration key, REST API key and client secret are secrets. Each is
encrypted at rest, masked (`[REDACTED]`) whenever configuration leaves the
system (e.g. API reads), never pre-filled when editing (leave the field blank to
keep the stored value), and never written to logs. Failures log only the first
four characters of the credential.

A stored secret belongs to its auth mode. Switching mode drops the other modes'
secrets, so switching back asks for them again. Entering a new client ID without
a new client secret drops the stored secret too.

## Configuration

| Field | Modes | Required | Description |
| --- | --- | --- | --- |
| `auth_mode` | all | no | `events_v2` (default), `rest_api_key` or `rest_oauth`. See [Choosing an auth mode](#choosing-an-auth-mode). |
| `routing_key` | `events_v2` | yes | Events API v2 integration key (32 characters). Secret. |
| `api_key` | `rest_api_key` | yes | REST API key. Secret. |
| `client_id` | `rest_oauth` | yes | OAuth app client ID. |
| `client_secret` | `rest_oauth` | yes | OAuth app client secret. Secret. |
| `subdomain` | `rest_oauth` | yes | Account subdomain, e.g. `acme`. |
| `service_id` | REST | yes | Service the incidents are opened on. |
| `from_email` | REST | yes | Email of a PagerDuty user, sent as the `From` header. |
| `region` | all | no | `us` (default) or `eu`. Picks the PagerDuty hosts (see [Networking](#networking--egress)). |
| `event_action` | all | no | `trigger` (default), `acknowledge` or `resolve`: the action for every record. |
| `action_field` | all | no | Record field (dot-paths supported) holding the action. Overrides `event_action` per record. |
| `dedup_key_template` | all | when acknowledging/resolving | Template for the dedup key that ties records to one incident. Required when `event_action` is `acknowledge`/`resolve` or `action_field` is set. In REST modes an `incident_id_template` can stand in for it. |
| `incident_id_template` | REST | no | Template for the incident ID to acknowledge or resolve. See [REST mode](#how-rest-mode-works). |
| `summary_template` | all | no | Incident title. Defaults to `Flux alert from pipeline <id>`. |
| `severity` | all | no | Default severity: `critical`, `error` (default), `warning` or `info`. |
| `severity_field` | all | no | Record field holding a severity to map (see [Severity](#severity)). |
| `severity_map` | all | no | JSON object mapping your severity values to PagerDuty's. |
| `urgency` | REST | no | `high` or `low` for every incident. Defaults to one derived from the severity (see [Severity](#severity)). |
| `priority_id` | REST | no | Priority to set on new incidents, e.g. `P53ZZH5`. |
| `escalation_policy_id` | REST | no | Escalation policy for new incidents. Defaults to the service's own policy. |
| `note_template` | REST | no | Note added to the incident for every record. |
| `source` | `events_v2` | no | The affected system. Defaults to `flux`. |
| `component`, `group`, `class` | `events_v2` | no | Optional PagerDuty classification fields. |
| `custom_details_template` | all | no | JSON object shown on the incident. Defaults to the whole record. |
| `client`, `client_url` | `events_v2` | no | Label and link back to Flux on the incident (`client` defaults to `Flux`). |

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

## How REST mode works

In the REST modes the dedup key becomes the incident's **incident key**, and
the same rules apply:

- **Trigger** creates an incident on the service with the summary as its title
  and the custom details as its body. If an incident with the same key already
  exists, PagerDuty refuses the duplicate and the sink counts the record as
  delivered, just as Events API v2 would merge it. A trigger without a dedup key
  gets a fresh key, so each one opens a new incident.
- **Acknowledge / resolve** update an incident by ID. When
  `incident_id_template` renders a value, that incident is updated directly,
  provided it belongs to the sink's service; an incident on any other service
  fails the record without being changed. A REST credential can reach every
  incident in the account, so this keeps record data from closing other teams'
  incidents. Otherwise the sink looks up the service's open incident with the
  record's dedup key. If none is open, the record is delivered without changing
  anything, just as Events API v2 ignores a resolve for an unknown key.
- **Notes.** With a `note_template`, every record also adds a note to its
  incident, including triggers that matched an existing incident. A note is
  never retried within a delivery. If adding it fails, the record fails and the
  pipeline retries it: the incident change is harmless to repeat, but the note
  may then appear twice.

Priority and escalation policy are set only when an incident is created. They
are not changed on later records.

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

REST incidents have an **urgency** rather than a severity. Unless `urgency` is
set, `critical` and `error` open **high**-urgency incidents and `warning` and
`info` open **low**-urgency ones.

## Custom details

By default the whole record is attached to the incident as its custom details.
To show a curated set instead, set **Custom Details** to a JSON object; its string
values are interpolated:

```json
{"metric": "{metric}", "value": "{value}", "host": "{payload.host}"}
```

In the REST modes the details become the incident's description, as JSON text.

## Testing the connection

**Test Connection** on the Sinks list never pages anyone.

- **Events API v2** sends a `resolve` for a random dedup key that no incident
  uses. It confirms the key is well-formed and accepted by the Events API
  without opening or closing anything. PagerDuty may accept events for a
  well-formed key that doesn't belong to a service, so send a real trigger to
  confirm routing end to end.
- **REST modes** read the configured service. That proves the credential works
  (for `rest_oauth`, that the app can get a token) and that the service exists.
  It does not check the requester email; a wrong one fails on the first real
  record.

## Rate limits & delivery

PagerDuty rate-limits the Events API per integration key and the REST API per
API key or OAuth app. The sink honors PagerDuty's `Retry-After` header on `429`
responses and retries transient `5xx` failures and network errors with
exponential backoff. A `400` (invalid event or incident) fails immediately with
PagerDuty's error message. In `rest_oauth` mode, a `401` fetches a new token
and retries once.

| Setting | Default | Allowed |
| --- | --- | --- |
| `max_attempts` | 3 | Whole number, 1–10 |
| `retry_delay_ms` | 500 | Whole number, 0–60000 |
| `timeout_ms` | | Whole number, 1–120000 |

A value outside these bounds fails validation when you save, and **Test
connection** reports it without contacting PagerDuty. With a dedup key, a
retried trigger is idempotent.

High-volume pipelines should aggregate or filter upstream. One record is one
incident change, and paging on every record is rarely what on-call wants. The
REST API is rate-limited more tightly than the Events API, and a REST
acknowledge or resolve by dedup key costs two requests (a lookup, then the
update).

## Networking / egress

Outbound HTTPS (TCP 443) to:

| Auth mode | US | EU |
| --- | --- | --- |
| `events_v2` | `events.pagerduty.com` | `events.eu.pagerduty.com` |
| `rest_api_key` | `api.pagerduty.com` | `api.eu.pagerduty.com` |
| `rest_oauth` | `api.pagerduty.com` and `identity.pagerduty.com` | `api.eu.pagerduty.com` and `identity.pagerduty.com` |

The Flux node's egress / NAT and any firewall allowlist must permit those hosts,
or delivery fails despite a valid credential.

## PagerDuty as an alert channel

With the same Enterprise license, alert rules on **Alerts** can page PagerDuty
alongside email, webhook and Slack. Paste the service's integration key into
**PagerDuty integration key** and choose a severity. The alert channel always
uses Events API v2: it only needs to open and close incidents, which an
integration key covers.

- Each firing triggers an incident whose dedup key is unique to the rule, so a
  rule that keeps firing updates its open incident instead of opening new ones.
  The rule's cooldown still applies.
- The incident summary names the rule and trigger; the trigger data is attached
  as custom details.
- The key is write-only: it is never shown again after saving. Leave the field
  blank when editing to keep it, or tick **Remove the PagerDuty channel**.
  Like the sink's key, it is encrypted at rest and kept out of alert history
  and logs.
- **Test** checks the key the same non-paging way as the sink's connection test.
