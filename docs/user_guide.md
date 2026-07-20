# Flux User Guide

This guide covers how to use the Flux web interface to manage pipelines, sinks, and system settings.

---

## Table of Contents

- [Getting Started](#getting-started)
- [Dashboard](#dashboard)
- [Managing Pipelines](#managing-pipelines)
- [Visual Pipeline Builder](#visual-pipeline-builder)
- [Managing Sinks](#managing-sinks)
- [System Settings](#system-settings)
- [User Settings](#user-settings)

---

## Getting Started

### Registration

Navigate to `/users/register` to create an account. Provide an email address and password (minimum 12 characters).

### Login

Flux supports two authentication methods at `/users/log-in`:

- **Password login**: Enter your email and password. Optionally check "Keep me logged in" for a persistent session (60 days).
- **Magic link**: Enter your email and click "Send magic link." A one-time login link is sent to your email. Click the link to log in without a password.

### Email Confirmation

New accounts receive a confirmation email. Click the confirmation link to verify your account. You can also confirm from the `/users/log-in/:token` page.

### Sudo Mode

Sensitive actions (changing email, changing password) require re-authentication. When prompted, enter your current password to confirm your identity. Sudo mode lasts 60 minutes before re-authentication is needed again.

### Authentication Flow

```mermaid
graph LR
    R[Register] --> C[Confirm Email]
    C --> L[Login]
    L --> D[Dashboard]
    M[Magic Link] --> L
```

---

## Dashboard

**Route**: `/dashboard`

The dashboard provides a real-time overview of your system's health. It displays metric cards and a system health summary, all updated live every 2 seconds.

### Metric Cards

| Card | Description |
|------|-------------|
| **Active Pipelines** | Number of pipelines with `active` status. Shows how many are currently running |
| **Events / Sec** | Rolling throughput over the last 60 seconds. Shows total processed count below |
| **Failed Messages** | Lifetime count of messages that failed processing. Yellow-highlighted when > 0 |

### System Health

Below the cards, a System Health panel shows summary stats: events/sec and active pipeline count.

All metrics update in real time via PubSub -- no page refresh needed.

---

## Managing Pipelines

**Route**: `/pipelines`

### Pipeline List

The pipeline list shows all pipelines in your organization in a table with:

- **Name** and optional description
- **Status** badge: Active (green), Paused (yellow), Stopped (gray)
- **Source queue** (the topic the pipeline consumes from)
- **Connected sinks** count
- **Last updated** timestamp

### Pipeline Actions

| Action | Description |
|--------|-------------|
| **Start** | Set pipeline to `active` and spawn a processing runner |
| **Pause** | Temporarily suspend processing (no new messages consumed) |
| **Resume** | Resume a paused pipeline |
| **Stop** | Fully stop the pipeline (must be explicitly restarted) |
| **Delete** | Remove the pipeline (confirmation dialog shown) |

Active pipelines auto-start when the application boots.

### Pipeline Statuses

```mermaid
stateDiagram-v2
    [*] --> Stopped: Created
    Stopped --> Active: Start
    Active --> Paused: Pause
    Paused --> Active: Resume
    Active --> Stopped: Stop
    Paused --> Stopped: Stop
```

### Pipeline Detail View

**Route**: `/pipelines/:id`

Shows read-only details for a single pipeline:

- Configuration card (source queue, destination queue, creation/update timestamps)
- Steps preview with type icons and config summaries
- Connected sinks list with enabled/disabled status and type
- Status action buttons (Start, Pause, Resume, Stop)
- Edit in Builder button (opens the visual builder)
- Delete button (danger zone, with confirmation)

---

## Visual Pipeline Builder

**Routes**: `/pipelines/builder` (new) | `/pipelines/:id/builder` (edit)

The visual builder is a full-screen canvas for constructing pipelines by dragging, connecting, and configuring nodes.

### Layout

The builder has three panels:

1. **Left sidebar** -- Node palette with draggable components
2. **Center canvas** -- React Flow diagram where you place and connect nodes
3. **Right sidebar** -- Configuration panel (changes based on selected node/edge)

### Available Node Types

**Processing nodes:**

| Node | Icon | Purpose |
|------|------|---------|
| Source | Arrow down | Queue consumer (entry point for data) |
| Filter | Funnel | Keep or drop messages based on field conditions |
| Transform | Arrow path | Extract and map fields (Map step) |
| Rename | Pencil | Rename a field in the data |
| Script | Code bracket | Custom Lua transformation (see [lua_scripting.md](lua_scripting.md)) |

**Output nodes:**

| Node | Purpose |
|------|---------|
| Queue | Publish to a destination queue for pipeline chaining |
| Sink nodes | One node per configured sink (HTTP, Postgres) -- dynamically listed from your enabled sinks |

### Building a Pipeline

1. **Name your pipeline** using the text input in the top config bar.
2. **Drag nodes** from the left palette onto the canvas.
3. **Connect nodes** by clicking and dragging from a node's output handle to another node's input handle.
4. **Configure nodes** by selecting them on the canvas -- the right panel shows type-specific configuration fields (e.g., field name, operator, and value for a Filter node).
5. **Save** by clicking the Save Pipeline button in the top bar.

If no sinks are configured yet, the palette shows an "Add Sink" link that navigates to `/sinks/new`.

### Source nodes consume a queue

A pipeline's Source node is a **queue consumer** -- it reads from one internal queue. The queue it consumes depends on the source type you configure:

| Source type | Consumes queue | Provisioned by |
|-------------|----------------|----------------|
| Queue | the queue name you enter | any producer publishing to that queue |
| Webhook | `webhooks.<path>` | `POST /api/webhooks/<path>`, or a matching webhook source |
| Scheduled Poll | `polling.<source>` (derived from the node label) | a matching scheduled-poll source |
| Kafka / SQS / Kinesis / Pub/Sub / RabbitMQ (Pro) | the connector's queue | the corresponding managed source |

> **Configuring a source node only wires the *consumer* side.** For Webhook and Scheduled Poll, the upstream endpoint/poller that *publishes* into the queue must still be provisioned separately -- for a webhook, by POSTing to `/api/webhooks/<path>` (or creating a webhook source with the same name); for a scheduled poll, by creating a scheduled-poll source whose id matches the derived `<source>`. A source node whose upstream is never provisioned will simply receive no data.

---

## Managing Sinks

**Routes**: `/sinks` (list) | `/sinks/new` (create) | `/sinks/:id/edit` (edit)

Sinks are output destinations where processed pipeline data is delivered.

### Sink List

The sink list shows all sinks in your organization:

- **Name** with type icon
- **Type** badge: HTTP, Postgres
- **Enabled/Disabled** status
- **Last updated** timestamp

### Sink Actions

| Action | Description |
|--------|-------------|
| **Test Connection** | Verify connectivity to the destination (HEAD request for HTTP, SELECT 1 for Postgres) |
| **Toggle Enable/Disable** | Enable or disable the sink without deleting it |
| **Edit** | Open the sink configuration form |
| **Delete** | Remove the sink (confirmation dialog shown) |

### Creating / Editing a Sink

The sink form has two sections:

**1. Basic Information:**
- Name (required, unique within your organization)
- Description (optional)

**2. Sink Type** (select one):

#### HTTP Sink
Send data as HTTP requests (webhooks).

| Field | Description |
|-------|-------------|
| URL | Destination URL |
| Method | POST, PUT, PATCH, or DELETE |
| Headers | Optional HTTP headers map |
| Authentication | Bearer token, Basic auth, or API key header |
| Timeout | Request timeout in seconds (default: 30) |
| Retry attempts | Number of retries on failure (default: 3) |

#### Postgres Sink
Insert data directly into a PostgreSQL table.

| Field | Description |
|-------|-------------|
| Mode | Internal (app's own database) or External (separate DB) |
| Database URL | Connection URL (external mode only) |
| Table | Target table name |
| Column Mapping | Map data fields to table columns (supports nested paths with dot notation) |
| On Conflict | Strategy for duplicate keys: `nothing`, `replace_all`, or `raise` |

In **External** mode Flux connects out to a database you run — see
[Connecting to external databases](connectors/external-databases.md) for the
port and firewall/egress-IP setup needed to reach it.

#### MySQL Sink
Insert data directly into a MySQL table (MySQL 5.7 and 8.0). Always connects to an
external database — see [MySQL Sink](connectors/mysql.md) for the full reference
and [Connecting to external databases](connectors/external-databases.md) for
networking.

| Field | Description |
|-------|-------------|
| Database URL | `mysql://user:pass@host:3306/database` |
| Table | Target table name |
| Column Mapping | Map data fields to table columns (supports nested paths with dot notation) |
| On Duplicate Key | Strategy for duplicate keys: `raise`, `ignore`, or `update` (upsert) |
| TLS/SSL | Connect to the database over TLS |

---

## System Settings

**Route**: `/system/settings`

System settings are restricted to users with the **owner** role. Non-owners see a 403 Forbidden page with an automatic redirect countdown.

### Teams Management

- View all teams in your organization
- Create new teams (name and optional description)
- Edit team name and description
- Delete teams

### Members Management

Members are managed per team. For each team you can:

- View members with their roles and status
- Add new members (by email, with role assignment, and first/last name fields)
- Edit member roles (Admin, Member, Viewer)
- Disable or re-enable members (soft-disable preserves history)
- Remove members (you cannot remove yourself)

See [rbac.md](rbac.md) for details on roles and permissions.

---

## User Settings

**Route**: `/users/settings`

Requires [sudo mode](#sudo-mode) (re-authentication with your current password).

### Change Email

Enter a new email address. A confirmation link is sent to the new address. Your email is not updated until you click the confirmation link.

### Change Password

Enter your new password (minimum 12 characters) and confirm it. Your password is updated immediately and all other sessions are logged out.
