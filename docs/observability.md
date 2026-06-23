# Observability

> **Flux Pro feature.** Freshness SLOs, volume baselines, and schema drift
> detection require a Pro license. On the Community edition the **Observability**
> page shows an upgrade prompt. See [Open-core architecture](architecture/open_core.md)
> for how features are gated.

Flux's observability detectors answer the questions data teams ask most about a
pipeline's *inputs*, using only message **metadata** — never payload contents:

- **Did the data stop arriving?** (freshness)
- **Is the volume suddenly off?** (volume baseline)
- **Did the shape of the data change?** (schema drift)

These run per **source** — the identifier in your webhook URL,
`POST /api/webhooks/:source` (e.g. `github` → the `webhooks.github` queue) — and
surface on the **Observability** page and on each pipeline's **Observability** tab.

## Table of Contents

- [The three detectors](#the-three-detectors)
- [Configuring a freshness SLO](#configuring-a-freshness-slo)
- [Reading source health](#reading-source-health)
- [Sending alerts](#sending-alerts)
- [How it works](#how-it-works)

---

## The three detectors

| Detector | What it watches | Alerts when |
| -- | -- | -- |
| **Freshness SLO** | Time since the last message per source | A source misses its expected arrival window (e.g. "github hasn't sent anything in 15 min") |
| **Volume baseline** | Rolling per-minute volume per source, with statistical change-point detection | Volume suddenly drops or spikes relative to its learned baseline |
| **Schema drift** | The set of top-level fields and their types on *passing* messages | A new field appears, a field disappears, or a field's type changes |

Schema drift is complementary to **schema validation** (which rejects messages
that violate a declared schema). Drift detection observes the shapes of messages
that *pass* and warns you about soft change before it becomes a hard failure.

## Configuring a freshness SLO

1. Open **Observability** from the sidebar.
2. Find the source card you want to watch.
3. In the **Freshness** panel, set the **expected interval** (in seconds) — the
   longest gap you expect between messages — and click **Save**.

The freshness state then reads:

- **On time** — a message arrived within the window.
- **Late** — the warning threshold has passed but the window has not fully elapsed.
- **Breached** — no message within the expected interval; an alert can fire.

## Reading source health

Each source card shows three panels:

- **Freshness** — last-seen time, the configured SLO window, and an on-time / late
  / breached badge.
- **Volume** — last-minute message rate vs. the learned baseline rate, with a
  steady / spike / drop badge.
- **Schema** — the current field count, when drift was last detected, and a
  stable / drift badge.

The per-pipeline **Observability** tab shows the same card filtered to that
pipeline's source. SLO configuration lives on the standalone Observability page.

## Sending alerts

Detectors don't notify on their own — they feed the
[alerting](user_guide.md) engine. On **Alerts**, create a rule with one of the
observability trigger types and attach email / webhook / Slack channels:

- **Source freshness SLO missed** (`freshness_slo`)
- **Source volume anomaly** (`volume_anomaly`)
- **Source schema drift** (`schema_drift`)

Rules respect cooldowns just like any other alert rule, so a flapping source
won't spam your channels.

## How it works

Detection is driven entirely by telemetry — there is no extra instrumentation in
your pipelines:

- `[:flux, :queue, :published]` (emitted on every accepted webhook) feeds the
  **freshness** last-seen timestamp and the **volume** counter.
- `[:flux, :webhook, :received]` carries a lightweight schema **fingerprint** — a
  stable hash of the payload's top-level keys and value types — plus the field
  count. The raw payload never leaves the request process, so drift is detected
  without ever storing or forwarding message contents.

See the [Operator manual](operator_manual.md#telemetry-events) for the full
telemetry event reference.
