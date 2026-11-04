# Changelog

Notable changes to Flux Community Edition. Releases are git tags (`vX.Y.Z`).
Connectors marked Pro or Enterprise are gated here: their types, forms and
upgrade prompts ship in this repository, and their adapters ship in the
commercial editions.

This file starts after v0.2.6. For earlier releases, see the git history between
tags.

## Unreleased

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
  - The rule applies wherever the edition's adapters check it: on save, at test
    connection, at delivery and at source start.
  - See [Server AWS Credentials](docs/operator_manual.md#server-aws-credentials).
- **Source credentials stay out of pipeline reads and exports.** Builder source
  configs (passwords, secret keys, tokens, client keys) are masked in the
  pipeline API and the version diff, and dropped from exports via the API, the
  download and the mix task. Previously any key with `read:pipelines` could read
  them. Source credentials are not encrypted at rest, and the builder no longer
  says they are.
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

- Builder canvas controls follow the app theme, and the React Flow attribution
  is hidden.
- Dependency upgrades: Oban 2.24.2, Phoenix LiveView 1.2.13, LiveDashboard
  0.9.1, Broadway 1.3.0, MyXQL 0.9.0, Swoosh 1.29.3. nimble_options stays at
  1.1.1, because 1.2.0 breaks `Broadway.start_link/2`.
- CI:
  - Dependabot proposes only minor and patch version updates, and groups
    security updates per package manager.
  - GitHub Actions get their own weekly update and run on their Node 24
    releases.

### Fixed

- gRPC pipelines built in the builder consume the source's `grpc.<channel>`
  queue.
