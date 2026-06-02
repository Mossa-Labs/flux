# RBAC (Role-Based Access Control)

Flux supports two RBAC modes, selected by config so the same codebase can run as **cloud (multi-tenant)** or **self-hosted** with minimal surface.

## Config

```elixir
# config/config.exs (or runtime)
config :flux, :rbac_mode, :team_centric   # default: self-hosted / dev
# config :flux, :rbac_mode, :org_centric  # cloud / full org membership
```

* **`:team_centric`** (default): Org access and role are derived from **teams** and **team_members**. No need to manage `organization_members`; optional default org when the user has no teams.
* **`:org_centric`**: Org access and role come from **organization_members**. Table is used; backfill ensures existing org owners get an owner row.

Same `Scope` shape and `can?/3` API in both modes.

## Scope

`Flux.Accounts.Scope` is built per user and carries:

* `user` — the current user
* `organization_id` — default/current org
* `organization_role` — role in that org (`owner`, `admin`, `member`, `viewer`)

**Org-centric:** Default org and role are loaded from `organization_members` (first by `inserted_at`).

**Team-centric:** Accessible orgs = distinct orgs from the user’s team memberships; default org = first such org; role = best role among the user’s teams in that org (admin > member > viewer). If the user has no teams, a single default org (e.g. from seeds) is used with a fallback role.

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

In team-centric mode, the effective org role is the **best** role among the user’s team memberships in that org.

## Seed users (dev)

Seeds create test data compatible with both modes:

* **Users**: `admin@flux.dev`, `member@flux.dev`, `viewer@flux.dev` (password: `password1234`).
* **Organization**: Flux Development (slug: `flux-dev`).
* **Teams**: Core, Analytics (under that org).
* **Team members**: Core → admin, member; Analytics → admin, viewer.
* **Organization members** (for org-centric): admin → owner, member → member, viewer → viewer.

Run `mix ecto.setup` (or `ecto.create`, `ecto.migrate`, `run priv/repo/seeds.exs`) to apply migrations and seeds.

## Deployment

* **Self-hosted / Docker**: Prefer `:team_centric`; no `organization_members` management; optional single default org from seeds.
* **Cloud / multi-tenant**: Use `:org_centric`; manage org members and roles via `organization_members`; backfill ensures existing org owners get an owner row.
