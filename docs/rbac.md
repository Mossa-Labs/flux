# RBAC (Role-Based Access Control)

Flux uses **team-centric** RBAC: organization access and roles are derived from a
user's team memberships, so a self-hosted deployment gets multi-tenant access
control without managing separate organization-member records.

## Config

```elixir
# config/config.exs (or runtime)
config :flux, :rbac_mode, :team_centric   # default
```

Org access and role are derived from **teams** and **team_members**. There is an
optional default org when the user has no teams.

## Scope

`Flux.Accounts.Scope` is built per user and carries:

* `user` — the current user
* `organization_id` — default/current org
* `organization_role` — role in that org (`owner`, `admin`, `member`, `viewer`)

Accessible orgs = the distinct orgs from the user's team memberships; the default
org = the first such org; the role = the **best** role among the user's teams in
that org (admin > member > viewer). If the user has no teams, a single default org
(e.g. from seeds) is used with a fallback role.

## Permission API

Use a single entrypoint for all permission checks:

```elixir
Flux.Permissions.can?(scope, action, resource_or_scope)
```

* **Scope**: `socket.assigns.current_scope` (or context scope).
* **Action**: e.g. `:view_pipelines`, `:create_pipeline`, `:edit_pipeline`, `:delete_pipeline`, `:run_pipeline`, `:view_sinks`, `:create_sink`, `:manage_teams`, `:view_members`, `:invite_member`, `:view_dashboard`.
* **Resource**: Optional; for most actions you can pass `nil` or the scope.

**Where to use:** LiveViews (before load/mutate, redirect or show forbidden if not allowed), contexts (return `{:error, :forbidden}` when `can?` is false), and layout (show/hide nav items by `can?/3`).

## Roles

* **owner** — full org control; can manage members and delete.
* **admin** — manage pipelines, sinks, teams, members; no org-level delete.
* **member** — create/edit pipelines and sinks, run pipelines.
* **viewer** — read-only (view pipelines, sinks, dashboard).

The effective org role is the **best** role among the user's team memberships in that org.

## Seed users (dev)

Seeds create test data:

* **Users**: `admin@fluxdata.tech`, `member@fluxdata.tech`, `viewer@fluxdata.tech` (password: `password1234`).
* **Organization**: Flux Development (slug: `flux-dev`).
* **Teams**: Core, Analytics (under that org).
* **Team members**: Core → admin, member; Analytics → admin, viewer.

Run `mix ecto.setup` (or `ecto.create`, `ecto.migrate`, `run priv/repo/seeds.exs`) to apply migrations and seeds.

## Deployment

Self-hosted deployments use team-centric RBAC: no separate organization-member
management is required, and an optional single default org can come from seeds.
