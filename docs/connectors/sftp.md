# SFTP Connector (Source)

SFTP is a **Pro** connector available as a **source** — it polls a remote SFTP
directory on a schedule, discovers new files by glob, streams and parses each one
into records, and lands each record onto Flux's internal queue, which your
pipeline then consumes. It opens the classic file-exchange path common in
healthcare, finance, and insurance: *drop a file on SFTP → transform / detect →
sink*.

> **Pro feature.** On the Community edition the SFTP source is gated: the type
> appears in the UI marked *Pro* and any saved config is rejected with an upgrade
> prompt. The real adapter ships in the Flux Pro / Enterprise edition. Activate a
> license to enable it. See [pricing](https://fluxdata.tech/pricing).

SFTP is a **pull** source: Flux dials out to your server, lists the configured
directory on each poll, and ingests files that have not been processed before.
Files are streamed (never loaded whole into memory), so large files ingest with a
bounded memory footprint.

## Auth matrix

| `auth_mode` | Description |
| --- | --- |
| `password` (default) | Username + `password` |
| `private_key` | Username + PEM `private_key` (RSA or Ed25519), optional `passphrase` |
| `cert` | OpenSSH user `certificate` + its `private_key`, optional `passphrase` |

Secrets (`password`, `private_key`, `passphrase`, `certificate`) are stored in the
source config and are masked (`[REDACTED]`) when configuration leaves the system
(e.g. API reads). Prefer key-based auth (`private_key` / `cert`) over `password`.

The remote host key is verified by default against the configured known-hosts /
fingerprint; an explicit opt-in accepts any host key for development only (logged
as a warning) — do not use it in production.

## Source configuration

| Field | Required | Description |
| --- | --- | --- |
| `host` | yes | SFTP server hostname or IP |
| `port` | no | SSH port (default `22`) |
| `username` | yes | SSH username |
| `path` | yes | Remote directory to poll (e.g. `inbound/`) |
| `file_pattern` | no | Glob matched against filenames in `path` (e.g. `*.csv`); default all files |
| `format` | no | `csv` (default), `jsonl`, or `xml` — how each file is parsed into records |
| `auth_mode` | no | One of the auth modes above (default `password`) |
| `password` | conditional | Required for `password` auth |
| `private_key` | conditional | Required for `private_key` and `cert` auth |
| `passphrase` | no | Optional passphrase protecting the private key |
| `certificate` | conditional | Required for `cert` auth (OpenSSH user certificate) |
| `schedule` | no | Cron expression controlling poll cadence (e.g. `*/5 * * * *`) |
| `poll_interval_seconds` | no | Fixed interval between polls if no `schedule` is set (default `300`) |
| `after_processing` | no | `leave` (default), `move`, or `delete` — what to do with a file once ingested |
| `archive_path` | conditional | Required for `move`; directory processed files are moved into |
| `require_complete_marker` | no | When `true`, a file `foo.csv` is only ingested once `foo.csv.complete` exists |

### File formats

- **CSV** — parsed with a configurable delimiter and quoting; the header row (when
  present) names the record fields.
- **JSON Lines** — one JSON object per line; a line that isn't a JSON object is
  wrapped as `{"raw": "<line>"}`.
- **XML** — repeated record elements are streamed and each is turned into a record
  map.

Each parsed record becomes one internal message published onto the source queue,
tagged with the originating `filename` in metadata.

### Example

```json
{
  "type": "sftp",
  "host": "sftp.partner.example.com",
  "port": 22,
  "username": "flux",
  "auth_mode": "private_key",
  "private_key": "-----BEGIN OPENSSH PRIVATE KEY-----\n...",
  "path": "inbound/",
  "file_pattern": "*.csv",
  "format": "csv",
  "schedule": "*/5 * * * *",
  "after_processing": "move",
  "archive_path": "processed/",
  "require_complete_marker": true
}
```

## Delivery semantics

- **Dedup / resume** — processed filenames are tracked, so a file is ingested once
  even across restarts. With `after_processing: leave` this tracking is what
  prevents re-ingestion; with `move` / `delete` the file is also removed from the
  polled directory.
- **Publish-then-advance** — records are published to the internal queue before a
  file is marked processed, so a crash mid-file re-ingests that file rather than
  dropping records (at-least-once at the file boundary).
- **Partial-write protection** — writers frequently upload into the same directory
  Flux polls. Use the `.complete` marker convention (`require_complete_marker:
  true`): upload `foo.csv`, then upload an empty `foo.csv.complete`, and Flux only
  ingests `foo.csv` once the marker appears. Without a marker, Flux guards against
  in-flight files with a size-stability check but the marker is the robust option.
- **Streaming** — files are read in chunks and parsed incrementally; a 100 MB file
  does not buffer in memory.

## Networking & firewall

Flux **dials out** to the SFTP server on the SSH port (default `22`). A source can
save with valid credentials and still fail to ingest if the network path is
blocked, so get the networking right before attaching it to a pipeline. Use **Test
connection** on the source form to verify reachability and auth up front.

The egress model is the same as for [external databases](external-databases.md):
the server sees the connection arriving from the **Flux server's egress IP** — in
cloud deployments usually a **NAT gateway's Elastic/static IP**. Add that IP to the
SFTP server's allow-list, and scope the SSH account to the exchange directory only.
