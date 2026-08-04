# Slack Connector (Sink)

Slack is a **Pro** connector available as a **sink** — it posts each processed
record as a message to a Slack channel. It closes the AI/alerting path
end-to-end: *ingest → transform / detect → notify Slack*, e.g. "an anomaly
detector fires and drops a message into `#alerts`".

> **Pro feature.** On the Community edition the Slack sink is gated: the type
> appears in the UI marked *Pro* and any saved config is rejected with an upgrade
> prompt. The real adapter ships in the Flux Pro / Enterprise edition. Activate a
> license to enable it. See [pricing](https://fluxdata.tech/pricing.html).

A Slack *sink* egresses processed records **out** of a pipeline to Slack over
HTTPS. It is not a queue backend or a source.

## Auth modes

Choose one of two authentication modes with `auth_mode`:

| `auth_mode` | Description |
| --- | --- |
| `webhook` (default) | Post to a Slack **Incoming Webhook** URL. Simplest — the URL targets a single, pre-selected channel. |
| `bot_token` | Post via `chat.postMessage` with a **bot token** (`xoxb-…`). Enables choosing the `channel` per sink and richer scenarios. |

| Field | Required | Description |
| --- | --- | --- |
| `webhook_url` | `webhook` mode | `https://hooks.slack.com/services/…` Incoming Webhook URL. Embeds a secret token. |
| `bot_token` | `bot_token` mode | Slack bot token (`xoxb-…`) with `chat:write` scope. |
| `channel` | `bot_token` mode | Target channel (`#alerts` or a channel ID). Ignored in webhook mode (the webhook fixes the channel). |
| `username` | no | Override the display name of the posting bot. |
| `icon_emoji` | no | Override the bot icon, e.g. `:rocket:`. |

Both `webhook_url` and `bot_token` are secrets: they are stored in the sink
config and masked (`[REDACTED]`) whenever configuration leaves the system (e.g.
API reads), and are never written to logs in full.

### Setting up an Incoming Webhook

1. Create (or open) a Slack app at <https://api.slack.com/apps>.
2. Enable **Incoming Webhooks** and **Add New Webhook to Workspace**.
3. Pick the destination channel and copy the generated
   `https://hooks.slack.com/services/…` URL.
4. Paste it into the sink's **Webhook URL** field with **Auth Mode = Incoming
   Webhook URL**.

### Setting up a bot token

1. In your Slack app, add the `chat:write` bot scope under **OAuth &
   Permissions** and install the app to the workspace.
2. Copy the **Bot User OAuth Token** (`xoxb-…`).
3. Invite the bot to the target channel (`/invite @your-bot`).
4. Set **Auth Mode = Bot token**, paste the token, and set the **Channel**.

## Message formatting

Each delivered record is posted as one message.

| Field | Description |
| --- | --- |
| `message_template` | Optional text template. `{field}` placeholders (dot-paths supported, e.g. `{payload.host}`) are interpolated from the record. When blank, the JSON-encoded record is posted. |
| `blocks_template` | Optional JSON array of [Block Kit](https://api.slack.com/block-kit) blocks for rich messages. Supports the same `{field}` interpolation. |

Example `message_template`:

```
🚨 Anomaly on {host}: {metric} = {value}
```

Example `blocks_template` (Block Kit):

```json
[
  {"type": "section", "text": {"type": "mrkdwn", "text": "*Anomaly* on {host}"}},
  {"type": "section", "text": {"type": "mrkdwn", "text": "`{metric}` = *{value}*"}}
]
```

## Rate limits & delivery

Slack rate-limits Incoming Webhooks (roughly 1 message/second per webhook) and
`chat.postMessage`. The sink honors Slack's `Retry-After` header on `429`
responses and retries transient `5xx` failures with exponential backoff. Sustained
high-volume pipelines should aggregate upstream rather than posting every record.

## Networking / egress

Outbound HTTPS (TCP 443) to `hooks.slack.com` (webhook mode) and `slack.com`
(bot-token mode). The Flux node's egress / NAT and any firewall allowlist must
permit those hosts, or delivery fails despite valid credentials.
