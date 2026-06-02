# RBAC System for Flux (Archived Plan)

> **Archived**: This planning document is historical. RBAC has been fully implemented. See [rbac.md](../rbac.md) and the RBAC section of [operator_manual.md](../operator_manual.md) for current documentation.

## Current state (from codebase and [architecture_overview.md](architecture_overview.md))

- **Control plane** is org-scoped: pipelines, sinks, and dashboard use `current_scope.organization_id` (user's "default" org = first org they *own*).
- **Organizations**: single owner via `user_id`; no other members. [Scope](app/lib/flux/accounts/scope.ex) has `user` and `organization_id` (no role).
- **Teams**: exist with `organization_id` and `user_id` (creator). [Structure](app/lib/flux/structure.ex) lists teams by `user_id` only; Team changeset does **not** set `organization_id`, so team–org linkage is incomplete.
- **TeamMember**: `user_id`, `team_id`, `role` (string, no enum). CRUD in Structure has **no scope** and is unused in the UI.
- **Authorization**: implicit only — "I am the org owner" or "resource.organization_id == scope.organization_id". No permission checks or roles.

So: teams and team_members are in the DB but not used for access control or UI.

---

## Feature flag: deployment mode (cloud vs self-hosted)

Flux supports **multi-tenant cloud** and **self-hosted / self-deploy** (e.g. Docker/container). RBAC is gated by a config flag so self-hosted users can use **team-centric only** (no org-members table to manage); cloud can use full **org-centric** RBAC.

- **Config**: `config :flux, :rbac_mode, :org_centric | :team_centric`
  - Default for dev/self-hosted: `:team_centric`
  - Cloud / multi-tenant: `:org_centric`
- **`:org_centric`**: Org access and roles come from `organization_members`. Table is used; backfill owners.
- **`:team_centric`**: Org access and roles are **derived from teams/team_members** (user in at least one team in that org; role = best role across those teams). `organization_members` table may exist but is **not read** for scope. Optional **default org** (e.g. single org from seeds) when user has no teams yet.

Same `Scope` shape and `can?/3` API in both modes; only the source of `organization_id` and `organization_role` changes.

---

## 1. Data model and migrations

**1.1 Organization membership (new)**

- Add table `organization_members` (used when `:rbac_mode == :org_centric`):
  - `id` (PK), `organization_id` (FK to organizations, on_delete: :delete_all), `user_id` (FK to users, on_delete: :delete_all)
  - `role` (:string, e.g. "owner" | "admin" | "member" | "viewer")
  - timestamps (:utc_datetime)
  - `unique_index(:organization_members, [:organization_id, :user_id])`, `index(:organization_members, [:user_id])`
- **Backfill migration**: For each `organizations` row, insert `organization_members` with organization_id, user_id: org.user_id, role: "owner" (on_conflict: :nothing for idempotency).
- Keep `organizations.user_id` as creator/owner for backward compatibility.

**1.2 Teams and team_members (team-centric path)**

- **Team schema** ([app/lib/flux/structure/team.ex](app/lib/flux/structure/team.ex)): In changeset set `organization_id` from scope (e.g. user_scope.organization_id) or from attrs so every team belongs to an org. Validate presence when creating from UI.
- **Migration (optional)**: Backfill existing teams where organization_id IS NULL (e.g. set to org for that team's user_id if deterministic).
- **TeamMember**: Validate `role` with validate_inclusion/3 (e.g. ["admin", "member", "viewer"]). Scope all CRUD by "user can access this team's org" (via scope).

**1.3 Role semantics**

- Org/team roles: owner, admin, member, viewer. Document which permissions each has. In team-centric mode, "best" role across a user's teams in an org determines scope.organization_role (e.g. admin > member > viewer).

---

## 2. Scope and "current org" behavior

**2.1 Extend [Scope](app/lib/flux/accounts/scope.ex)**

- Add to struct: `organization_role` (nil or string). Optionally `organization_membership` (OrganizationMember struct).

**2.2 When `:rbac_mode == :org_centric`**

- Resolve default org from `organization_members` (e.g. first by inserted_at). Load membership for that org; set scope.organization_id, scope.organization_role.
- If no membership, fall back to orgs where user is owner (organizations.user_id); backfill ensures they have an organization_members row.

**2.3 When `:rbac_mode == :team_centric`**

- "Accessible orgs" = distinct teams.organization_id from team_members join teams where team_members.user_id == user.id.
- Default org = first such org (or only org in single-tenant). Role = best role among user's team_members in that org (admin > member > viewer).
- If user has no teams (e.g. fresh self-hosted): use a **default org** (e.g. single org from seeds) and assign implicit role (e.g. "owner" for seed admin).

**2.4 Backward compatibility**

- Existing code only uses scope.organization_id. Backfill ensures org owners have organization_members in org-centric mode. In team-centric mode, scope is derived from teams; default org fallback keeps single-tenant working.

---

## 3. Permission API and usage

- Add `Flux.Permissions.can?(scope, action, resource_or_scope)`. Implementation uses scope.organization_role (and optionally scope.user and resource). Same can?/3 in both rbac_mode values.
- Use in LiveViews (before load/mutate), contexts (accept scope, return {:error, :forbidden} when not allowed), and layout (show/hide nav items).

---

## 4. Seeds: test accounts and structure

Pre-create test data compatible with both modes ([app/priv/repo/seeds.exs](app/priv/repo/seeds.exs)):

- **Users**: admin@flux.dev, member@flux.dev, viewer@flux.dev (shared password e.g. password1234).
- **Organization**: Flux Development (slug: flux-dev).
- **Teams** (under that org): Core, Analytics.
- **Team members**:
  - Core: admin@flux.dev → admin, member@flux.dev → member.
  - Analytics: admin@flux.dev → admin, viewer@flux.dev → viewer.
- **Organization members** (meaningful when :org_centric): admin@flux.dev → owner, member@flux.dev → member, viewer@flux.dev → viewer.

Seeds can create all of the above unconditionally; interpretation depends on rbac_mode.

---

## 5. Docs updates

- **docs/architecture_overview.md**: Extend Data Model with team_members and organization_members (when used). Add short "Authorization and RBAC" subsection (Scope fields, :rbac_mode, org-centric vs team-centric).
- **New docs/rbac.md**: Describe org-centric vs team-centric modes, how Scope is built in each, can?/3 usage, and seed users/permissions. Optionally deployment (self-hosted vs cloud).
- **docs/development_roadmap.md** (optional): Note RBAC v1 feature-flagged for self-host vs cloud.

---

## 6. Implementation order (concrete steps)

| Step | Task |
|------|------|
| 1 | Add config :flux, :rbac_mode (default :team_centric). Migration: create organization_members; backfill owners. |
| 2 | Schema and context for OrganizationMember; ensure owner is added when creating an org (when org_centric). |
| 3 | Extend Scope: add organization_role; compute default org and role from organization_members (org_centric) or from teams/team_members (team_centric). |
| 4 | Add Flux.Permissions.can?/3; implement rules for org role to actions. |
| 5 | Fix Team: set organization_id in changeset; scope team list/get by org access. Scope TeamMember CRUD; validate role enum. |
| 6 | Seeds: users, org, teams, team_members, organization_members (as above). |
| 7 | Docs: architecture_overview.md, new docs/rbac.md (and optionally roadmap). |
| 8 | LiveViews: call can?/3 where appropriate; redirect or show forbidden when not allowed. Layout: show/hide nav by can?/3. |
| 9 | (Optional) Org switcher and session-stored current org. |

---

## 7. Summary

- **Feature flag** `:rbac_mode` (:org_centric | :team_centric) supports cloud (full org members) and self-hosted (team-centric only, optional default org).
- **Data model**: organization_members table (with backfill); Team and TeamMember fixed and scoped; roles validated.
- **Scope** built from organization_members in org_centric mode, from teams/team_members in team_centric mode; same struct shape and can?/3 API.
- **Seeds**: three users (admin, member, viewer), one org, two teams, team_members and organization_members as above.
- **Docs**: architecture_overview and new rbac.md updated for RBAC and deployment modes.
