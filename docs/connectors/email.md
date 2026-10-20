# Email Sink

The Email sink sends an email for each pipeline record, rendering the subject and
body from templates. It is a **Community** connector (available on all tiers).
Typical uses are alerts and notifications: a failed order, a threshold crossed, a
record that needs a human to look at it.

It can send through your own SMTP server, through the mail server this Flux
instance is already configured with, or through SendGrid, Mailgun, Postmark or
Amazon SES.

## Configuration

### Sender, recipients and message

| Field | Required | Description |
| --- | --- | --- |
| `provider` | yes | `smtp`, `system`, `sendgrid`, `mailgun`, `postmark`, or `amazon_ses` |
| `from` | yes¹ | Sender address |
| `from_name` | no | Sender display name (at most 78 characters) |
| `reply_to` | no | Reply-To address |
| `to` | yes | One or more recipient addresses |
| `cc`, `bcc` | no | Further recipients |
| `subject` | yes | Subject template |
| `html_body` | no | HTML body template |
| `text_body` | no | Plain-text body template |
| `rate_limit.max_per_minute` | no | Emails per minute for this sink, per node (default `30`) |
| `rate_limit.max_wait_ms` | no | How long an over-limit record waits for the next minute before it is dropped (default `30000`) |

¹ Optional for the `system` provider, which defaults to `FLUX_MAIL_FROM_ADDRESS`.

Recipients are fixed in the sink's configuration. They are never taken from the
record, so data flowing through a pipeline cannot redirect mail. A sink can have
at most 50 recipients across `to`, `cc` and `bcc`.

### Providers

| Provider | Fields |
| --- | --- |
| `smtp` | `host` (required), `port` (default `587`, or `465` with `ssl`), `security`, `username`, `password`, `tls_verify` |
| `system` | None. Uses the server configured with `FLUX_SMTP_*` (see the operator manual) |
| `sendgrid` | `api_key` |
| `postmark` | `api_key` (the server token) |
| `mailgun` | `api_key`, `domain` (your sending domain), `region` (`us` default, or `eu`) |
| `amazon_ses` | `region`, `access_key`, `secret_access_key` |

API providers also accept an optional `base_url` to point at a regional or
compatible endpoint, such as SendGrid's EU API.

`password`, `api_key` and `secret_access_key` are encrypted at rest and are never
shown again after saving. When editing a sink, leave them blank to keep the stored
value.

### SMTP security

| `security` | Meaning |
| --- | --- |
| `starttls` (default) | Connects in plain text, then upgrades with STARTTLS. Fails if the server does not offer it rather than sending your credentials in the clear |
| `ssl` | TLS from the first byte (usually port 465) |
| `none` | No encryption. Only for internal relays on a trusted network |

The server's certificate is verified against the operating system's trust store.
For an internal relay with a self-signed certificate, set `tls_verify` to `false`
("Skip TLS certificate verification" in the form). Doing so makes the connection
open to interception, so don't use it across the internet.

## Templates

`subject`, `html_body` and `text_body` take `{field}` placeholders, filled from
each record. Dot-paths reach into nested values:

```text
Order {order.id} for {customer.name} failed: {error.message}
```

- Strings are inserted as-is, numbers and booleans as text, and maps and lists as
  JSON. A missing field renders as nothing.
- In `html_body`, every inserted value is HTML-escaped, so a record cannot inject
  markup or scripts. Your template's own HTML is kept as written.
- In `subject`, line breaks are collapsed, so a record cannot add mail headers.

Which body is sent depends on which templates are set:

| Templates set | Email sent |
| --- | --- |
| Both | Multipart: HTML, with your plain-text version as the alternative |
| `html_body` only | Multipart: HTML, with a plain-text version derived from it |
| `text_body` only | Plain text |
| Neither | Plain text containing the record as pretty-printed JSON |

Every email carries `Auto-Submitted: auto-generated`, so mail servers and
out-of-office responders don't reply to it.

## Addresses

Every address is checked when the sink is saved, and the form flags a bad
recipient as you type. Flux accepts the shape of address modern mail systems
deliver to:

- **Length**: at most 254 characters in total, 64 before the `@`, and 63 for each
  part of the domain.
- **Before the `@`**: letters, digits and ``.!#$%&'*+/=?^_`{|}~-``, with no
  leading, trailing or doubled dot. Quoted forms like `"john doe"@example.com`
  are not accepted.
- **Domain**: at least two parts (`example.com`, not `localhost`), each made of
  letters, digits and hyphens. The last part can't be all digits, and IP
  addresses like `[192.0.2.1]` are not accepted.
- **ASCII only**: internationalized addresses such as `josé@example.com` are not
  supported yet.

No DNS lookup is made, so an address on a domain that doesn't receive mail still
saves. Use a test send to confirm delivery.

## Delivery and rate limits

Delivery is **fire-and-forget**, like every Flux sink: the pipeline acknowledges a
record whether or not its email is sent, and a failed send is logged rather than
retried later.

To keep a busy pipeline from getting your sender flagged as spam, each sink sends
at most `max_per_minute` emails per minute. A record over the limit waits up to
`max_wait_ms` for the next minute and is then **dropped** with a
`rate_limited` warning in the log. Only as many records wait as one minute can
send (`max_per_minute`). Beyond that, records are dropped immediately, so a
burst doesn't pile up thousands of waiting deliveries. The limit is counted on
each Flux node separately, so a cluster of N nodes can send up to
N × `max_per_minute`.

If a pipeline produces bursts, filter or aggregate upstream so the sink sees the
records worth an email.

## Testing the connection

The **Test** action on the sinks page checks the transport without sending mail:

- `smtp`: connects, negotiates TLS and logs in, then disconnects.
- `system`: reports whether this Flux instance has a mail server configured.
- API providers: there is no side-effect-free way to check their credentials, so
  the test always passes. A wrong key shows up as a delivery error in the log.

## Example

```json
{
  "type": "email",
  "provider": "smtp",
  "host": "smtp.example.com",
  "port": 587,
  "security": "starttls",
  "username": "flux-alerts",
  "password": "s3cret",
  "from": "alerts@example.com",
  "from_name": "Pipeline Alerts",
  "to": ["ops@example.com", "oncall@example.com"],
  "subject": "Order {order.id} failed",
  "html_body": "<p>Order <b>{order.id}</b> failed: {error.message}</p>",
  "text_body": "Order {order.id} failed: {error.message}",
  "rate_limit": {"max_per_minute": 20}
}
```

## Testing locally

The adapter's unit tests run with the normal suite, including the API providers,
which are exercised against a local stub of each provider's HTTP API.

The SMTP integration tests need a real SMTP server and are excluded by default
(`@tag :integration`). They use [Mailpit](https://mailpit.axllent.org), which
requires STARTTLS, accepts any login, and exposes an API the tests use to check
what arrived:

```bash
docker compose -f docker-compose.mailpit.yml up -d
cd app && mix test --include integration test/integration/email_sink_test.exs
```

To try the sink by hand, create one with provider `smtp`, host `localhost`, port
`1025`, any username and password, and "Skip TLS certificate verification"
checked, then open http://localhost:8025 to see what it sends.
