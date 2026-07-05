# Backstage Governance & RBAC Foundation — Attijari Portal

> Decoupled, role-based, Keycloak-anchored.
> Status: **ENFORCED** (2026-07-05). `allow-all` replaced by the local
> `permissionPolicy` module (backstage `20260705-1410`); group membership +
> public-offering data wired. See "Implementation — delivered" below.

## Context

The Permission Framework is already wired in Backstage (`permission.enabled: true`,
`@backstage/plugin-permission-backend`) **but running the `allow-all` policy** — nothing is enforced
yet. Identity is already IdP-derived: the generic `http-entities` connector ingests Keycloak
**Users** (`kind: User`) and **Groups** (`kind: Group`), but **flat** — no `parent`/`children`/
`memberOf`, so no hierarchy or ownership graph today. A binding one-identity contract already exists
(`team-<slug>` everywhere, provider-first ownership, "visible if `owner ∈ userGroups` OR
`platform.kratix.io/public=true`", `role ∈ {provider, consumer}`). This document defines the
governance foundation before we replace `allow-all` with a real policy.

## Design reasoning

1. **Hierarchy source.** Keycloak is the single identity source (one-identity contract) and supports
   nested groups; Backstage's org model (`Group.parent/children/members`, `User.memberOf`) maps 1:1.
   Derive the hierarchy from Keycloak subgroups — never hand-author it (a second identity format is
   forbidden). *Gap:* the current `keycloakGroups` block emits groups flat; extend the mapping
   (config only) to emit `parent`/`children`/`memberOf`.
2. **Decoupling.** Four independent concerns in four layers so each can change alone: identity/org
   (Keycloak), projection (http-entities), roles/permissions (Backstage RBAC), supply-chain (GitOps
   merges). A *role* is a binding above the identity source — not a Keycloak object, not per-user
   code — so "who is a provider" (Keycloak attribute) and "what a provider may do" (Backstage
   binding) are two independent knobs.
3. **Ownership = visibility lever.** Backstage resolves `ownershipEntityRefs` to the user plus every
   ancestor group (transitive `memberOf`+`parent`). Placement of `spec.owner` sets the blast radius;
   own by **Group, never User**. Top-level tribe ownership is seen by all descendant squads.
4. **Enforcement.** Replace allow-all with default-deny + conditional allow. Read = `isEntityOwner`
   OR `hasAnnotation(public=true)`; writes/executes branch on the role bound from the Keycloak `role`
   attribute. Decisions read the **catalog projection**, never Keycloak at request time — that is the
   decoupling in practice (swap Keycloak for AD = a config block, roles untouched).
5. **State of the art.** Backstage org model + Permission Framework conditional decisions
   (`isEntityOwner`/`hasAnnotation`) + community RBAC plugin for first-class, admin-managed roles;
   groups-own-not-users; identity-derived-from-IdP; default-deny.

## Group Hierarchy Design

Keep Keycloak as the single identity source (`team-<slug>` everywhere) and **derive** the Backstage
org graph from it. Two tiers: **top-level groups = tribes / business domains** (`team-platform`,
`team-retail`, `team-risk`) as `Group` entities with no `spec.parent`; **squads = leaf groups**
(`team-payment`, `team-vente`) with `spec.parent` → their tribe and `spec.type: squad`. Every user is
`memberOf` their squad(s) and transitively their tribe — so a user always belongs to ≥1 group. Extend
the `httpEntities.keycloakGroups` block to walk Keycloak subgroups and emit `parent`/`children`, and
the users block to emit `memberOf` — config only, no second identity format, no code. Carry `role` as
a Group annotation (`platform.kratix.io/role`) sourced from a Keycloak group attribute, not a
parallel tree.

## Decoupled Model & Defined Roles

Govern in **four decoupled layers**, each with one concern:

1. **Identity & organisation — Keycloak (source of truth).** AuthN (OIDC client `backstage`), the
   user directory, the tribe→squad hierarchy (subgroups), and a per-group `role` attribute
   (`provider` | `consumer`; the platform tribe carries `platform-admin`). Keycloak answers *who* and
   *which group* — nothing about Backstage permissions.
2. **Projection — the `http-entities` connector (bridge).** Reads Keycloak's admin API and emits
   catalog `User`/`Group` entities (`parent`/`children`/`memberOf` + `role` annotation). This bridge
   decouples the IdP wire format from the catalog: adding AD/Harbor/an API later is *a config block*,
   the layers above untouched.
3. **Roles & permissions — Backstage RBAC (decision layer).** Named roles bound to projected
   groups/attributes → concrete permissions. Decisions read the **catalog projection**, never Keycloak
   at request time, so the IdP and the permission engine stay independent.
4. **Supply-chain gate — GitOps merges (orthogonal).** The portal-templates / platform-gitops
   double-human-merge controls what actually lands, on top of RBAC.

### Defined roles (bound from Keycloak, enforced in Backstage)

| Role | Bound from (Keycloak) | Can | Owns |
|---|---|---|---|
| `platform-admin` (infra plane) | group `cluster-admins` / tribe `team-platform` | own platform/shared entities; publish/curate base promises (execute promise-factory); full catalog read. Real power is cluster + GitOps, **not** portal governance | platform / shared entities |
| `backstage-admin` (portal plane) | dedicated group `backstage-admins` → `permission.rbac.admin.users` | manage RBAC role→permission bindings, register/unregister/refresh catalog locations, edit the policy; portal superuser | — (governs, doesn't own products) |
| `provider` | squad, attribute `role=provider` | read owned+public; execute promise-factory + product templates; create/edit/own Promise, Template & `kratix-promise` fiche | its product promises & templates |
| `consumer` | squad, attribute `role=consumer` | read owned+public; execute product templates (request claims); own resulting instances | its `kratix-resource` instances |
| `viewer` | authenticated, no squad / guest | read public entities only; no execute | — |

**Two admin planes, decoupled (separation of duties).** The **platform admin** (infra) is the
platform-engineering tribe, already bound to the existing Keycloak `cluster-admins` group
(platform-identity `ClusterAdmin`); its authority is the cluster, GitOps and the base-promise supply
— a provider-of-providers. The **Backstage admin** (portal) is a *separate* dedicated group
(`backstage-admins`) wired to the RBAC plugin's `permission.rbac.admin.users`; it governs the portal
itself (role bindings, locations, policy) and owns no products. The two overlap in a small team today
but must stay independent roles — whoever decides "who sees what" in the portal is not necessarily
cluster-admin, and vice versa.

A role is a **binding** (`group | attribute → role → permissions`) — not a Keycloak object, not
per-user code. Two independent knobs: change who is a provider in **Keycloak** (the group's `role`
attribute) or what a provider may do in **Backstage** (the binding); neither touches the other.
Implement the binding with the community RBAC plugin (`@backstage-community/plugin-rbac`, UI +
DB-backed, audit log, first-class `admin.users`/`superUsers`) for admin-managed roles; a code-level
conditional `PermissionPolicy` reading the same annotation is the lighter fallback.

## Ownership & Access Rules

Ownership is always a **Group, never a user** (continuity). `spec.owner` placement is the visibility
lever (transitive `ownershipEntityRefs`): (1) platform-wide/shared entities → `team-platform`; (2) a
product's Promise, pushed Template and `kratix-promise` fiche → the **providing squad**
(`group:default/team-<provider>`, provider-first); (3) a provisioned instance (`kratix-resource`) →
the **requesting consumer squad** (owner-hérité via the `component-of-owner` label). An entity is
discoverable when `owner ∈ user's groups` **or** it carries `platform.kratix.io/public=true`.

## RBAC Policy Mapping

Replace `allow-all-policy` with a conditional `PermissionPolicy` (default-deny + explicit allow),
expressed per role. `catalog.entity.read` →
`createConditionalDecision(anyOf(isEntityOwner(ownershipRefs), hasAnnotation('platform.kratix.io/public','true')))`
for every role. Product-entity writes (`catalog.entity.create/delete/update`) → the entity **owner**
(provider) or `platform-admin` for platform/shared entities. Portal-governance writes —
`catalog.location.create/delete`, entity refresh/unregister, and the RBAC plugin's own
`policy.entity.*` (role bindings) — → **`backstage-admin` only**. `scaffolder.action.execute` on
product templates → allow if public or owned; the promise-factory publish flow → `provider` +
`platform-admin`, `consumer` denied. The role that gates each write is bound from the Keycloak `role`
attribute (or `cluster-admins`/`backstage-admins` group) — RBAC mirrors ownership, the
provider/consumer split, and the infra/portal admin split.

## Provider / Consumer Considerations

**Providers (fournisseurs)** — squads with `role=provider`: execute the promise-factory, own the
resulting Promise/Template/`kratix-promise` fiches, and are the `spec.owner` on product templates.
**Consumers (consommateurs)** — squads with `role=consumer`: browse public offerings, execute product
templates (request claims) and own the resulting instances, but cannot create or edit promises
(denied on factory execute and promise-fiche create/delete). The `platform.kratix.io/role` annotation
drives the branch; Kratix `requiredPromises` + the merge gates remain the supply-chain control on top
of RBAC.

## Best Practice Alignment

Follows Backstage's documented org model (`parent`/`children`/`members`, `memberOf`, transitive
`ownershipEntityRefs`) and Permission Framework guidance (conditional decisions with
`isEntityOwner`/`hasAnnotation`, default-deny). The community RBAC plugin
(`@backstage-community/plugin-rbac`) gives first-class, admin-managed, auditable roles decoupled from
both code and the IdP. Ownership-by-group, identity-derived-from-Keycloak, roles-as-bindings, and
RBAC-mirrors-ownership are all state-of-the-art; the one-identity contract and provider-first
ownership already in place make the mapping direct.

## Implementation — delivered (2026-07-05)

Staged in two backstage rollouts to avoid a catalog blackout (membership must resolve *before*
enforcement, or ownership refs are empty):

1. **Group membership (data).** The generic `http-entities` connector gained two source-agnostic
   primitives — `expand` (per-item sub-fetch) and `specLists` (array-valued specs + `slugify`). The
   `keycloakGroups` source now fetches `/groups/{id}/members` → `Group.spec.members` (slugified) →
   Backstage derives `memberOf` on users → `ownershipEntityRefs` at sign-in. Verified live: `erin →
   group:default/team-vente`, admins → `group:default/cluster-admins` (LDAP-federated users included).
2. **Public offerings (data).** `backstage-component` 0.4.10 stamps `platform.kratix.io/public=true`
   on product Templates + `kratix-promise` fiches (knob `BACKSTAGE_PUBLIC`, default true). The
   promise-factory sets `BACKSTAGE_PUBLIC=false` → the meta-promise stays platform/provider-only.
   Verified live: 12 public offerings (6 templates + 6 fiches), factory private.
3. **Enforcement (policy).** Local `permissionPolicy` module (`packages/backend/src/modules/`)
   replaces `allow-all`: admin bypass on `cluster-admins`/`backstage-admins`; `catalog.entity.read`
   = conditional `isEntityOwner | hasAnnotation(public=true) | isEntityKind(User,Group)` (org
   directory world-readable so owner refs resolve); portal-governance writes (create/delete/refresh,
   locations) = admins only; everything else = allow. Proven by 6/6 unit tests + clean backend init.

### Follow-ups (documented, not blocking)

- **`backstage-admins` group** as identity-as-code (platform-identity) — today the infra plane
  (`cluster-admins`) covers both admin planes (the ref is already honored by the policy).
- **`role` attribute in Keycloak** (`provider`/`consumer`) surfaced as `platform.kratix.io/role` on
  Group entities — currently offerings are public-to-all + factory-restricted, which covers the
  provider/consumer *visibility* split; the attribute enables finer per-action gating.
- **Scaffolder-execute hardening** — deny task-create on unreadable templates (today the factory is
  hidden by read + the double-merge gate stops any consumer-opened PR from landing).
- **Tribe→squad hierarchy** — requires Keycloak subgroups (flat groups today); `spec.parent` wiring
  is a config-only add to `keycloakGroups` once subgroups exist.
- **Community RBAC plugin** (`@backstage-community/plugin-rbac`) — swap-in for UI-managed, auditable
  role bindings when non-engineers must administer roles.

### Final human verification (needs a real OIDC login — the user's gesture)

Sign in as `erin` (team-vente, non-admin): should see the 12 public offerings + her team-vente
instances, the org directory, but **not** the promise-factory nor other squads' instances; an
admin (`alice`) sees everything. Guest sign-in is disabled in production.
