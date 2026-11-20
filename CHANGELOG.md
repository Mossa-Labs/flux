# Changelog

Notable changes to Flux Community Edition. Releases are git tags (`vX.Y.Z`).
Connectors marked Pro or Enterprise are available in the Flux Pro / Enterprise
edition; Community shows them with an upgrade prompt.

This file starts after v0.2.6. For earlier releases, see the git history between
tags.

## 0.2.8 — 2026-11-20

### Upgrade notes

- **Queues are now per organization. This release can't be rolled out node by
  node.** A pipeline's `source_queue` and `destination_queue`, a webhook's
  `webhooks.<source>` queue and a poll's `polling.<source_id>` queue are now
  logical names that Flux places inside the owning organization (organization
  42's `webhooks.github` is the broker queue `org.42.webhooks.github`). Every
  message carries its organization, and a pipeline drops any message that
  doesn't carry its own. Before upgrading:
  1. Run `bin/flux eval "Flux.Release.audit_queue_names()"` and rename every
     pipeline it lists. A queue name that starts with `org.`, `amq.` or
     `flux.`, or uses characters other than letters, digits, `_`, `.` and `-`,
     is now refused, and a pipeline that already has one won't start.
  2. On a broker-backed queue, drain the old queues, then stop every node.
  3. While every node is stopped, delete any broker queue whose name already
     starts with `org.` (a pipeline chose that name; the new release would
     consume it as that organization's queue). Then start the new release.
  - Messages still in queues under the old names aren't consumed any more.
    See [Upgrading](docs/operator_manual.md#upgrading) for how to deal with
    them.
  - `POST /api/webhooks/:source` now answers 400 for a `source` that isn't a
    plain name (letters, digits, `_`, `.`, `-`, at most 128), and 403 for an
    API key that isn't tied to an organization. The pipeline builder refuses
    to save a webhook path whose last segment the endpoint would reject.
  - Poll jobs need an `organization_id` argument; a job without one is
    cancelled.
  - For queue adapter authors: `Flux.Queue.publish/4` and
    `Flux.Queue.producer_spec/3` take the organization; adapters receive
    physical queue names, must implement `message_organization_id/1` alongside
    `producer_spec/1`, and the DLQ callbacks take the organization as their
    first argument. See the [developer guide](docs/developer_guide.md).

- **Postgres sinks in internal mode now write only to the `sink_data` schema.**
  The sink's table name must be a plain name (letters, digits, underscores)
  and resolves inside `sink_data`, never to another schema. External mode is
  unchanged. Before upgrading:
  1. Create the schema: `CREATE SCHEMA IF NOT EXISTS sink_data;`. The release
     migration also creates it, but that needs the `CREATE` privilege on the
     database. If the app's database role doesn't have it, create the schema
     as an administrator and grant the role `USAGE, CREATE` on it.
  2. Move each internal-mode target table, for example
     `ALTER TABLE events SET SCHEMA sink_data;`.
  - Deliveries to a table that hasn't been moved fail and are logged, not
    retried, so move the tables before the new release starts processing.
- **Stop every node before you migrate. This release can't be rolled out node
  by node.** Two data migrations encrypt existing source configs and the source
  credentials in pipeline steps (including every version snapshot). They
  rewrite rows in `sources`, `pipelines` and `pipeline_versions`. A node still
  on the previous release reads those columns as plain maps, so it would hand
  ciphertext to its source adapters and show it in the pipeline builder. Plan a
  short maintenance window:
  1. Stop all Flux nodes.
  2. Run the migrations.
  3. Start the new release.
  - Rolling back: stop the new release, run the database rollback (it decrypts
    again), then start the older release.
  - See [Secret Encryption at Rest](docs/operator_manual.md#secret-encryption-at-rest).
- **Behind a reverse proxy, set `FLUX_TRUSTED_PROXIES`.** Flux now reads
  `X-Forwarded-For` only from the proxies it lists. Earlier releases also
  trusted any peer in a private range without being told to. If an L7 load
  balancer sits in front of Flux and the variable is unset, Flux sees the
  proxy's address as the client, and an organization's IP allowlist judges
  every API request by it. Set it to your proxies' addresses before upgrading.
  See [IP Allowlist](docs/operator_manual.md#ip-allowlist).

### Security

- **Queues are isolated per organization** (MOS-674). Queue names used to be
  shared by every organization, so a pipeline in one organization could consume
  another organization's webhooks, and a webhook, poll or destination queue
  could publish into another organization's pipelines. Queue names are now
  placed inside the owning organization on the server, messages carry their
  organization and pipelines refuse any other, and queue names that reach
  outside the organization are refused on every write path. Dead-letter
  listing, retry, discard, replay and depth are scoped to the organization too.
- **System Settings actions stay in the caller's organization** (MOS-671).
  Member and API key actions could reach records outside the organization the
  page manages. They now look records up only within it, and every action
  re-checks the caller's role first.
- **A pipeline only uses its own organization's sinks** (MOS-672). A pipeline
  could reference another organization's sink and deliver to it with that
  sink's stored credentials. Such a sink is now refused on every write path,
  skipped at run time, and dropped when rolling back to an older version.
- **Internal Postgres sinks are confined to the `sink_data` schema** (MOS-673).
  An internal-mode sink could write to any table the app's database role could
  reach, including Flux's own. See the upgrade note above.
- **`X-Forwarded-For` is trusted only from configured proxies** (MOS-603). Any
  client could choose the IP address Flux saw by sending the header, and so get
  around an organization's IP allowlist.
- **Alert-channel secrets are encrypted at rest and write-only** (MOS-662).
  Slack and webhook URLs are no longer sent to the browser: the form leaves
  them blank, a blank field keeps the stored value, and testing a rule happens
  on the server.
- **Source credentials are encrypted at rest** (MOS-654). Source configs and the
  source credentials the pipeline builder keeps in a pipeline's steps are now
  stored as ciphertext, like sink configs. This covers passwords, SASL passwords,
  AWS secret keys and session tokens, Pub/Sub credentials, MQTT JWTs, SFTP and
  mTLS private keys, and gRPC bearer tokens and metadata. Adapters and the
  builder read plaintext as before.
- Source config redaction now also masks AWS secret keys and session tokens,
  Pub/Sub credentials, MQTT JWTs and gRPC metadata, which it previously missed.
- Dependency security updates:
  - ecto 3.14.3 (EEF-CVE-2026-118391)
  - plug 1.20.4 (EEF-CVE-2026-120287)
  - idna 8.0.0 (EEF-CVE-2026-117678), with swoosh 1.30.0
  - phoenix_live_view 1.2.14 (EEF-CVE-2026-126334)

### Added

- **PagerDuty sink: REST API auth modes** (Enterprise, MOS-661). Besides the
  Events API v2 integration key, the sink can authenticate to the PagerDuty REST
  API with an API key or a Scoped OAuth app (client credentials). REST mode adds
  urgency, priority, escalation policy, incident notes, and acknowledge/resolve
  by incident ID. The OAuth client secret is a new sink secret, encrypted at
  rest and redacted like the others. Existing sinks keep using Events API v2.
  See [PagerDuty](docs/connectors/pagerduty.md#choosing-an-auth-mode).
- **Single sign-on (SAML)** (Enterprise, MOS-481). Members can sign in with an
  identity provider such as Okta, Microsoft Entra ID or Google Workspace, from
  a new "Sign in with SSO" option on the login page. A new Single sign-on tab
  in System Settings sets it up, maps IdP groups to roles, and can require SSO
  for the whole organization; turning that on signs out the organization's
  non-owner members. On Community and Pro the tab shows an upgrade prompt. See
  [Single sign-on](docs/sso.md).

### Changed

- Dependency upgrades: Broadway 1.3.1, lazy_html 0.1.14, and nimble_options
  1.2.0, which 0.2.7 held back and Broadway 1.3.1 works with.

### Fixed

- A changeset error on a list-typed or encrypted field (for example a
  non-numeric `sink_ids` entry) returned a server error from the API, the
  pipeline import task and the alerts page instead of a validation message.
- A sink or source secret that can't be decrypted with the current vault key
  no longer breaks every page and query that reads it (MOS-665, MOS-666). The
  sinks list flags the sink as needing its credentials re-entered, a source
  with such a secret refuses to start or test and says which secret, and either
  can still be disabled.
- Selecting a Redact PII or Classify step in the pipeline builder crashed the
  page.

## 0.2.7 — 2026-11-04

### Upgrade notes

- **Run migrations before you start the new release.** Oban moves from 2.20 to
  2.24 and needs its schema at version 14. A node that starts first fails with
  "Oban migrations are outdated".
  - The migration adds two indexes to `oban_jobs` without `CONCURRENTLY`, so a
    large table blocks inserts briefly while they build.
  - Nodes still on 0.2.6 keep working against the new schema.
  - See [Upgrading](docs/operator_manual.md#upgrading).
- **Pipeline API responses now mask source credentials.**
  `GET /api/pipelines/:id`, create and rollback return the credentials the
  builder keeps in a pipeline's steps as `"[REDACTED]"`, and pipeline exports
  drop them. Scripts that read credentials back from the API will see the mask,
  and an imported pipeline needs its source credentials re-entered.
- **Upgrade prompts name the edition that unlocks a feature**, for example
  "requires Flux Enterprise" instead of "requires Flux Pro". Update anything
  that matches the old text.

### Security

- **Operators can stop AWS connectors from using the server's own AWS
  identity.** Set `FLUX_AWS_SERVER_CREDENTIALS=disabled` when several
  organizations share a deployment. Otherwise a member could use the server's
  role (`iam_role`, or `assume_role` without base keys) to reach another
  organization's buckets, tables, queues or streams. The default, `allowed`,
  keeps today's behaviour.
  - With it disabled, the S3, DynamoDB, Cassandra SigV4, SQS and Kinesis forms
    offer only static keys or `assume_role` with base keys.
  - Connectors that would use the server's identity are refused on save, at
    test connection, at delivery and at source start.
  - See [Server AWS Credentials](docs/operator_manual.md#server-aws-credentials).
- **Source credentials stay out of pipeline reads and exports.** Builder source
  configs (passwords, secret keys, tokens, client keys) are masked in the
  pipeline API and the version diff, and dropped from exports via the API, the
  download and the mix task. Earlier releases returned them to any API key that
  could read pipelines. Source credentials are not encrypted at rest, and the
  builder no longer says they are.
- Dependency security updates:
  - plug_crypto 2.2.1 (EEF-CVE-2026-105963)
  - bandit 1.14.1 (EEF-CVE-2026-116078)
  - phoenix_html 4.4.0 (EEF-CVE-2026-117645)

### Added

- **gRPC source** (Enterprise): connector type, builder form for server and
  client mode, and docs. Messages land on the `grpc.<channel>` queue. See
  [gRPC](docs/connectors/grpc.md).
- **PagerDuty sink and alert channel** (Enterprise): connector type, sink form
  (severity defaults to `error`), a PagerDuty channel on alert rules, and docs.
  See [PagerDuty](docs/connectors/pagerduty.md).
- **Cassandra sink** (Pro), for Apache Cassandra, ScyllaDB and Amazon Keyspaces:
  connector type, form and docs.
  - Keyspaces writes must use `local_quorum`.
  - SigV4 signing with server credentials reaches only Keyspaces endpoints.
  - See [Cassandra](docs/connectors/cassandra.md).
- A **Flux Enterprise** group in the sink picker.
- **Base keys for `assume_role`** in the DynamoDB, Cassandra SigV4 and SQS
  forms, so a role can be assumed without the server's identity.
- Docs:
  - a [connectors index](docs/connectors/README.md);
  - an Alerts section in the user guide;
  - an upgrade procedure in the operator manual;
  - gRPC telemetry and observability coverage.

### Changed

- Builder canvas controls follow the app theme.
- Dependency upgrades: Oban 2.24.2, Phoenix LiveView 1.2.13, LiveDashboard
  0.9.1, Broadway 1.3.0, MyXQL 0.9.0, Swoosh 1.29.3.
