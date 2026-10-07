# BeachVolleyballProject: Organisation Tree, Details, and Polymorphic Memberships

Updated: 7 October 2026

## 1. Goal and scope

Replace the busy organisation catalogue with a clean, expandable tree inspired by Wine Words `Regions.tsx`. Clicking an organisation name opens `OrganisationDetails.tsx`. The detail page contains organisation information, members, child organisations, join/request actions, and permitted management controls.

An organisation can have an **Account**, an unlinked **PlayerProfile**, or an unlinked **CoachProfile** as a member. On successful profile claim or invitation acceptance, profile-held memberships transfer to the linked Account. An Account can have multiple PlayerProfiles and CoachProfiles; those profiles remain intact.

Provide a general member search across all three types. Show organisation links on Player, Coach, and Account pages. Extend the Identity page so users can find organisations, join eligible organisations, request membership, and track requests.

This is an implementation plan, not an implemented change. Proposed endpoints, fields, services, and components below must be added or adapted. Group membership is outside this refactor, but its organisation eligibility checks must continue to work.

## 2. Repository baseline inspected

| Repository | Inspected revision | Relevant sources |
| --- | --- | --- |
| [Frontend](https://github.com/romalopes/beachvolleyballproject) | `16c5438` | `src/pages/Organisations.tsx`, `OrganisationDetail.tsx`, `Identity.tsx`, `PlayerDetail.tsx`, `CoachDetail.tsx`, `AccountDetail.tsx`, `src/api.ts`, `src/App.tsx` |
| [Rails API](https://github.com/romalopes/beachvolleyballproject_api) | `78bb45b` | Organisation and membership models/controller, `ClaimSubject`, claim/invitation services, profile ownership and candidate services, `db/schema.rb` |
| [Visual reference](https://github.com/romalopes/wine_words_front_end/blob/main/src/components/Regions.tsx) | Read from main during the previous planning pass | Separate expansion buttons, recursive indentation, linked names, compact metadata |

Recheck the repositories before implementation; these are snapshots rather than a claim about future main branches.

### Already implemented

- `Organisations.tsx` builds a collapsible hierarchy from flat records carrying `parent_organisation_id`.
- `GET /api/v1/organisations?tree=1` returns the complete filtered hierarchy without pagination.
- `/organisations/:id` and `OrganisationDetail.tsx` already exist; the page currently shows basic information.
- The catalogue contains inline edit/create forms, logo upload, archive/restore, delete, and `OrganisationRoster`.
- Membership roles are `owner`, `administrator`, `coach`, and `member`; statuses are `pending`, `active`, `suspended`, and `ended`.
- The current membership model belongs to **Account**, not Person. The current schema has an `account_id` index unique per organisation and account when present.
- The model enforces one active owner per organisation and preserves ended membership history.
- Per-record API flags include `can_edit`, `can_delete`, and `can_manage_members`.
- Identity already lists account memberships and supports claims and invitations.
- Approved claims and accepted claim invitations both call `ClaimSubject#effect!`, which currently only links the profile to an Account.

### Gaps and compatibility risks

- Organisation names in the tree are currently plain text.
- “Show archived” currently switches to archived-only, rather than including archived records.
- The detail endpoint supports some ordinary organisation members, while catalogue/member endpoints remain training-manager restricted. Roster filtering also limits what non-managers see.
- Roster UI/API helpers retain legacy person naming and identifiers while the Rails membership endpoint uses Account IDs. Reconcile these deliberately.
- Account-based membership queries are used by visibility, permissions, group eligibility, claim candidate filtering, and Identity serialization. Updating only the membership model would break these consumers.

Do not replace a hypothetical `person_id` reference without inspecting the actual schema. This repository needs an Account-to-polymorphic migration with compatibility support.

## 3. Membership rules

### Canonical member resolution

| Selected subject | Membership stored against |
| --- | --- |
| Account | That Account |
| PlayerProfile with no linked Account | That PlayerProfile |
| CoachProfile with no linked Account | That CoachProfile |
| PlayerProfile already linked to Account | Its linked Account |
| CoachProfile already linked to Account | Its linked Account |

The server resolves the canonical member. Do not trust the frontend to normalize linked profiles. Recheck ownership under a lock when saving: a profile can be claimed between search and selection.

Use `member_type` and `member_id` for the polymorphic subject. Allowlist only `Account`, `PlayerProfile`, and `CoachProfile`; do not call arbitrary `constantize` on client input.

An Account membership represents belonging to an organisation. A profile represents volleyball activity and is not an independent permission principal. Selecting a CoachProfile does not automatically assign the organisation role `coach` or grant roster-management permission.

### Profile and Account display after linking

- Unlinked profiles display their direct organisation memberships.
- Linked profiles display effective organisation memberships through their Account, plus any unresolved transfer items appropriately labelled.
- Account pages display canonical Account memberships and permitted transfer history.
- An Account linked to a player profile in Club A and a coach profile in Club B shows both memberships. Both linked profile pages can show both organisations, labelled “Through linked Account”. Preserve source-profile provenance so the original association remains understandable.
- Do not count linked profiles as additional members when their Account already represents them.
- Unclaimed profiles may represent the same person without the system knowing it. They remain separate provisional roster entries until verified linkage; never merge by name or email alone.

### Permission defaults

- Unlinked profile memberships can describe `member` or `coach` roles. New `owner` or `administrator` assignments require an Account.
- Management authority derives only from a canonical, active Account membership and existing site permissions.
- Claiming a profile does not grant privileged roles, unsuspend an Account, approve a pending membership, or bypass organisation policy.
- Organisation hierarchy does not automatically confer membership or management rights in descendants.
- Profile creation rights and organisation roster-management rights are separate checks. A coach may manage a profile without permission to add it to every organisation.

## 4. Proposed Rails data model

### OrganisationMembership

Conceptual final association:

```ruby
belongs_to :organisation
belongs_to :member, polymorphic: true
```

For a new schema, the reference would be:

```ruby
t.references :member, polymorphic: true, null: false
```

For the existing database, add nullable columns, backfill, then constrain them in later migrations. Do not add `null: false` to populated rows before backfilling.

| Field | Purpose |
| --- | --- |
| `organisation_id` | Existing organisation foreign key |
| `member_type`, `member_id` | Canonical polymorphic member |
| `role`, `status` | Existing organisation role and lifecycle |
| `joined_at`, `left_at` | Existing dates; transfer must preserve them |
| `superseded_by_id` | Nullable self-FK identifying a consolidated membership |
| `created_by_account_id` | Optional actor attribution for new writes, if not already available |

Add:

- Non-null subject columns after validated backfill.
- Database allowlist check for `member_type`.
- Unique partial index on `(organisation_id, member_type, member_id)` where `superseded_by_id IS NULL`.
- Reverse lookup index on `(member_type, member_id)`.
- Self-FK and checks preventing self-supersession; application rules prevent supersession cycles.
- Preserve the one-active-owner constraint, adapting its predicate to exclude superseded rows.
- Preserve role/status and ended-membership timestamp constraints.

Use an `effective` scope that excludes superseded rows. All permission, roster, count, and eligibility queries must deliberately use it. A superseded source can retain its original status and dates for history, but can no longer confer membership or authority.

Polymorphic subjects cannot use one ordinary foreign key to three tables. Use type/existence validation, transaction-safe services, and deletion restrictions on each member model. Hard deletion of a referenced subject must be blocked unless a reviewed history-preserving process handles it. Keep the real FK to Organisation. Do not specify a conventional polymorphic `foreign_key: true` expecting cross-table integrity.

### Associations and services

- Add `has_many :organisation_memberships, as: :member` to Account, PlayerProfile, and CoachProfile.
- Preserve convenient organisation associations with clearly named active/effective variants.
- Introduce `OrganisationMemberResolver` for allowed type lookup and canonicalization.
- Introduce `OrganisationMembershipPolicy` and scoped discovery/search services.
- Introduce `EffectiveOrganisationMemberships` for consistent reads across profiles and accounts.
- Introduce `OrganisationMembershipTransferService` for linkage and consolidation.
- Reuse existing application audit infrastructure if suitable; otherwise add a dedicated immutable transfer ledger.

### Transfer ledger

Record each transfer with source profile, source membership, destination Account and membership, actor, claim/invitation reference, timestamp, outcome, before/after snapshots, and conflict reason. Keep identifiers and snapshots readable even after source archival. Add a unique operation key so retries cannot duplicate audit events.

Outcomes can be `transferred`, `consolidated`, or `needs_review`. Pending conflict records require a resolved timestamp, resolving actor, decision, and reason. Pending conflicts preserve the original subject and membership as historical evidence; they are excluded from effective access after linkage.

### OrganisationMembershipRequest

Use a separate request table instead of overloading a membership's `pending` status. An application and a provisional roster record are different workflows.

Fields: organisation FK, requesting Account FK, status (`pending`, `approved`, `rejected`, `cancelled`), optional message, reviewed-by Account FK, reviewed timestamp/reason, resulting membership FK, and timestamps.

Enforce one pending request per organisation and Account through a partial unique index. The request endpoint always derives the Account from the authenticated user.

### Organisation join policy

Add `membership_policy` with `open`, `approval_required`, and `closed` values. Recommended default for new organisations: `approval_required`.

- `open`: self-service creates or explicitly reactivates an eligible `member` membership.
- `approval_required`: create a request; authorised officers approve or reject it.
- `closed`: self-service unavailable; permitted staff additions remain governed by current policy.
- Archived organisations cannot accept self-service joins or requests.

Existing organisations currently have self-service join behaviour. Preserve their behaviour during migration by backfilling `open`, then let authorised administrators change their policy explicitly. Do not silently convert existing organisations to approval-required.

## 5. Transfer after claim or invitation acceptance

Extend the existing linkage boundary used by `ClaimSubject#effect!`, or delegate it to one shared linking service. Every sanctioned path that assigns `profile.account_id` must invoke the same operation: claim approval, token redemption, received-invitation acceptance, authorised direct linking, and backfill/repair jobs.

Never transfer when a claim is merely requested, rejected, cancelled, or pending.

### Transaction algorithm

1. Verify the existing claim/invitation and linking authorisation rules.
2. Lock the profile, destination Account, and affected memberships in a documented consistent order. Audit existing callers so outer locks do not reverse that order. Retry database deadlocks within bounded limits.
3. Recheck the profile's linked Account and current membership subjects under the locks.
4. Gather direct memberships, including ended/history rows, excluding already completed supersession operations.
5. Resolve one organisation at a time using the rules below.
6. Link the profile and write transfer/audit records in the same database transaction.
7. Commit the claim/invitation result atomically. A database failure rolls back both linkage and membership changes. A recorded business conflict can allow linkage to finish while the membership remains unavailable pending review.
8. Refresh effective memberships and publish any notifications only after commit.

Concurrent inserts must be guarded by unique indexes and bounded retry/re-read logic; locks on existing rows alone do not prevent duplicate new rows.

### Duplicate and conflict rules

| Situation | Recommended result |
| --- | --- |
| No Account membership for that organisation; source is ordinary member/coach | Repoint source to Account, retain role/status/dates, record original profile in ledger |
| Compatible Account membership already exists | Keep the Account membership canonical; mark source superseded; preserve both histories |
| Account active; source pending or ended | Keep Account active without overwriting its dates; retain source history |
| Account active; source active with same ordinary role | Consolidate without creating another member; retain source interval in ledger |
| Account pending/ended; source active | Flag for review; do not silently approve/reactivate Account membership |
| Account suspended; source active | Flag for review; never bypass suspension |
| Different roles or conflicting dates/status | Flag for review; keep Account's current effective record |
| Unexpected source owner/administrator role | Flag for review; never transfer management privileges automatically |
| Only historical source membership exists | Transfer as ended; it grants no current access |
| Same profile linked again to the same Account | Idempotent no-op or completion of an unfinished transfer |
| Profile linked to another Account | Reject through existing ownership rules; no transfer |

Do not use “highest role wins” or a universal status ranking. Do not invent a continuous membership interval by combining the earliest join date and latest leave date across gaps. Preserve the original episodes in audit/history even if the canonical record remains one row.

After linkage, no unresolved profile row may grant effective access. Display its pending transfer under the Account and organisation review screens, with visibility appropriate to the actor. Approved conflict resolution must record an explicit decision and preserve source history.

Retain historical source membership IDs or a stable resolution mapping so old API/bookmark references and related records remain explainable. Profile merging must transfer or preserve remaining memberships and unresolved conflicts before source archival; use the same conflict rules.

## 6. General member search

Proposed endpoint:

```text
GET /api/v1/organisations/:id/member_candidates?q=Maria&type=all&page=1
```

Return a paginated, permission-scoped result set across Account, PlayerProfile, and CoachProfile. Accept only supported type filters. Use existing searchable name fields; add indexes where query plans justify them.

Example candidate contract:

```json
{
  "key": "PlayerProfile:42",
  "selected_subject": { "type": "PlayerProfile", "id": 42 },
  "canonical_member": { "type": "Account", "id": 7 },
  "display_name": "Maria Jose Silva",
  "kind_label": "Player profile",
  "linked_account": { "id": 7, "display_name": "Maria Jose Silva" },
  "membership": { "id": 88, "status": "active", "role": "member" },
  "can_add": false,
  "reason": "Already a member through linked Account"
}
```

- Distinguish identical numeric IDs using `type:id` keys.
- Present Account results with matching linked profiles grouped underneath where feasible. Unlinked profiles stay independent.
- Explain when a selected profile resolves to an Account.
- Mark existing active/pending/suspended/ended memberships accurately. An ended row is a reactivation candidate, not automatically a fresh insert.
- Debounce search and ignore/cancel stale requests; cap page size.
- Search only subjects the acting manager may discover and add. “General” means all supported types, not unrestricted access to all accounts or private profile contact information.
- Do not expose email, address, or phone by default. Do not use name similarity to prove ownership.
- Archived/merged profiles must not be offered for new additions.

Search visibility and write permission are both checked server-side, including when a caller submits a candidate ID that was not returned by search.

## 7. Organisation catalogue UI

Keep `/organisations` and the current tree API. Extract a reusable tree node/component with semantic nested lists, ordinary links, and separate buttons; avoid declaring `role=tree` unless full tree keyboard behaviour is implemented.

Each row shows expansion control, logo/acronym fallback, linked name, type, status, and immediate child count. Optional member counts must distinguish active canonical members from provisional unclaimed profiles and be returned only where permitted.

Controls:

- Search by organisation name/acronym.
- Active / Archived / All status filter.
- Expand all / Collapse all.
- Existing permitted New organisation action.
- Minimal optional per-row actions; detailed editing/roster controls move to the detail page.

Search retains ancestor paths and expands them. Clearing search restores prior expansion state. A filtered-out parent must not make its child disappear; show the detached branch with available parent information. Preserve arbitrary depth and standalone organisations. Add visited-ID protection for malformed hierarchy data and retain server cycle validation.

Clicking the expansion button only expands/collapses. Clicking the name opens `/organisations/:id`. Preserve browsing filters and expansion state when returning from details, using URL/local route state as appropriate.

## 8. OrganisationDetails.tsx

Rename the existing `OrganisationDetail.tsx` and update imports; preserve the route `/organisations/:id`.

Header: logo/acronym, name, type/status, parent or accessible breadcrumb, Back to organisations, and the appropriate Joined / Request pending / Join / Request membership action. For users without catalogue access, provide Back to Identity instead.

| Tab | Content |
| --- | --- |
| Overview | Existing description, acronym, type, status, parent, permitted summary counts, join policy |
| Members | Mixed subject roster, type badges, links, role/status filters, general member search and permitted management |
| Sub-organisations | Immediate children and their detail links, with access-aware loading |
| Requests | Pending join requests and membership-transfer conflicts for authorised reviewers |
| Management | Existing edit/logo/archive/restore/delete controls and authorised join-policy editing |

Persist selected tab as `?tab=members`. Validate tab values and avoid exposing restricted tab contents through query manipulation.

Load Overview first. Lazy-load Members, Requests, and children. Keep each tab's error state independent. Distinguish a forbidden roster from an empty roster. Abort/ignore stale responses after changing organisation IDs and clear old record state. Validate route IDs and support direct links, refresh, 403, 404, and retry.

Refactor existing `OrganisationRoster`, forms, and actions into shared components. Roster writes use **membership IDs**, not person/account IDs, so any member type is addressable. A canonical Account appears once; its linked profiles may appear as subordinate links rather than duplicate roster entries.

Retain history, partial logo-upload success messaging, deletion conflicts, and the existing distinction between editing an organisation and managing its roster. Superseded rows and unresolved transfers continue to block destructive history loss.

## 9. Player, Coach, Account, and Identity pages

### Shared organisation links panel

Create `OrganisationMembershipLinks.tsx` for PlayerDetail, CoachDetail, AccountDetail, and the user's Account page. Include organisation name/link, membership role/status, and origin label (`Direct profile membership` or `Through linked Account`). Separate current membership from pending/history entries; deduplicate organisation IDs within each applicable category.

Keep ended, pending, suspended, and unresolved-transfer labels explicit; do not style them as current active memberships. Provide links only where the caller may read the destination; otherwise show permitted non-linked text. No client-side workaround for a 403.

In Players/Coaches lists, add a compact permitted organisation summary or badge; detailed data remains on the detail page. Bulk-serialize summaries to avoid one request per row.

### Identity self-service

Extend the existing Organisation memberships section with:

1. My organisations, linked to their detail pages.
2. Find organisations: searchable, paginated discovery of allowed organisations, with policy labels.
3. Join action for open organisations.
4. Request membership for approval-required organisations, with optional message.
5. My requests: pending, approved, rejected, cancelled; cancel only pending requests.
6. Membership history and claim-related transfer notices.

Self-service membership always belongs to the authenticated Account. The user cannot choose another Account, add unclaimed profiles, or select their own privileged role.

Joining an organisation is distinct from claiming a profile. Membership does not prove ownership of any profile. Claim eligibility may use approved active membership as context, but a pending request is not enough. Open joins must not expose private claim candidates or become a loophole for unrelated profile claims; preserve independent coach/organisation claim boundaries and review rules.

Do not make the full management catalogue public simply to implement self-service. Add a scoped discovery endpoint returning minimal information for authenticated users. Detail and roster permissions remain separate.

## 10. API contracts and authorisation

Preserve existing organisation routes where practical. Proposed additions/changes:

| Endpoint | Purpose |
| --- | --- |
| `GET /organisations?tree=1` | Existing manager catalogue, with explicit status-filter semantics |
| `GET /organisations/discover` | Minimal authenticated organisation discovery for self-service |
| `GET /organisations/:id` | Existing detail, extended capabilities and caller's membership/request summary |
| `GET /organisations/:id/children` | Scoped, paginated immediate children |
| `GET /organisations/:id/members` | Polymorphic roster, scoped and preferably paginated |
| `GET /organisations/:id/member_candidates` | General member search for permitted roster managers |
| `POST /organisations/:id/members` | Create/canonicalize selected subject under staff permission |
| `PATCH /organisations/:id/members/:membership_id` | Update permitted role/status |
| `DELETE /organisations/:id/members/:membership_id` | Existing end/withdraw semantics, not blanket hard deletion |
| `POST /organisations/:id/join` | Open-policy self join as ordinary member |
| `POST /organisations/:id/membership_requests` | Approval-required self request |
| `GET /me/organisation_membership_requests` | Current Account's request history |
| `POST /organisation_membership_requests/:id/cancel` | Requester's pending-request cancellation |
| `GET /organisations/:id/membership_requests` | Authorised review queue |
| `POST /organisation_membership_requests/:id/approve` | Authorised approval and membership creation/reactivation |
| `POST /organisation_membership_requests/:id/reject` | Authorised rejection with reason |
| `POST /organisation_membership_transfers/:id/resolve` | Authorised conflict resolution with recorded decision |

All paths are under `/api/v1`. Final naming should follow project conventions. Define collection routes before ID routes where needed. Existing member routes use account identifiers; introduce distinct versioned/explicit routes or a coordinated migration. Never reinterpret an old account ID path silently as a membership ID.

Proposed staff-add payload:

```json
{
  "membership": {
    "member_type": "PlayerProfile",
    "member_id": 42,
    "role": "member"
  }
}
```

Response includes membership ID, organisation summary, normalized member type/ID/display name, status/role/dates, permitted subject links, and caller capabilities. Return canonicalization information when a selected linked profile becomes an Account member. Prefer `member_name` over legacy `person_name`; retain temporary response aliases only during the compatibility window.

Capability fields can include `can_view_members`, `can_manage_members`, `can_review_requests`, `can_join`, `can_request_membership`, and `can_change_membership_policy`. Existing `can_edit` alone must not imply permission to change join policy or elevate member roles.

Roster visibility retains current privacy by default. If ordinary members should browse the full roster later, implement that explicitly as a separate policy change. Parent/child links do not expand readable scope.

## 11. Migration and rollout

### Expand

1. Inventory every Account membership query, serializer, constraint, route, deletion blocker, and profile linkage path.
2. Add nullable polymorphic columns, supersession support, transfer ledger, request table, and join-policy field.
3. Keep Account compatibility reads/writes temporarily. Account subjects dual-write the legacy account_id; provisional profile subjects keep it null only after legacy consumers safely tolerate this.
4. Add feature flags for profile roster additions and self-service requests. Keep new writes off until consumers understand polymorphic membership.

### Backfill

5. Map every valid legacy account_id to member_type Account/member_id account_id. Inspect nullable legacy rows; quarantine/report unresolved rows rather than fabricating subjects.
6. Check duplicate subjects, missing Accounts, owner conflicts, invalid dates, and existing live behaviour. Preserve IDs, timestamps, roles, and statuses.
7. Backfill existing organisation policies to open to preserve existing join behaviour. Default newly created organisations to approval_required.
8. Run resumable validation and discrepancy reports before enforcing non-null/check/index constraints.

### Switch

9. Move permission, visibility, `mine`, member counts, Identity, group eligibility, profile candidate search, and account/profile serializers to effective polymorphic queries.
10. Deploy generalized search/member APIs and frontend contracts. Enable provisional profile membership writes only after safe API/frontend rollout.
11. Integrate transactional transfer into all linkage paths. Repair any linked-profile memberships created during rollout using the same audited service.
12. Enable tree/details updates, request workflow, and effective organisation links.

### Contract

13. Remove legacy person/account route ambiguity and compatibility aliases only after callers are migrated.
14. Remove redundant legacy account_id column/index/FK in a separate migration after validated cutover.
15. Keep audit and superseded-source history. Monitor transfer conflicts and request handling.

Back up before migrations. Provide dry-run/backfill reports and tested recovery procedures. Once profile memberships exist, a rollback to Account-only code is not safe without a conversion strategy. Prefer disabling new features and forward-fixing; do not delete profile memberships to make a rollback appear clean.

## 12. Implementation phases with AI prompts

Run phases in order. Each prompt assumes the previous phase has passed its relevant checks. Repository code is authoritative for actual class/route names.

### Phase 0 — Audit and agree contracts

```text
Inspect romalopes/beachvolleyballproject and beachvolleyballproject_api.
Read current organisation models/controllers/routes/schema, frontend API types,
Organisations, OrganisationDetail, Identity, Player/Coach/Account pages,
ClaimSubject, PlayerClaimService, ClaimInvitationService, and profile merge paths.

Inventory all organisation_memberships account_id reads/writes, management checks,
visibility scopes, group eligibility, deletion blockers, and identity serializers.
Confirm the actual Account-based schema; do not assume Person membership exists.

Document the normalized polymorphic API contract and member-ID route transition.
Use canonical Account membership for linked profiles and provisional membership
for unlinked PlayerProfile/CoachProfile. Keep all existing profile records.
Produce a concrete migration/rollout checklist before modifying behaviour.
```

### Phase 1 — Polymorphic model and safe migration

```text
Implement an expand/backfill/contract migration for OrganisationMembership.
Add member_type/member_id for Account, PlayerProfile, and CoachProfile.
Preserve existing data, IDs, roles, lifecycle dates, and one-active-owner rule.
Add effective/superseded semantics, appropriate partial unique indexes,
allowed-type checks, deletion protection, and transfer audit infrastructure.

Implement an allowlisted OrganisationMemberResolver. Linked profiles resolve to
their Account; unlinked profiles retain their own subject. New unlinked profile
memberships cannot grant owner/administrator privileges.

Backfill current account_id rows through a resumable operation. Report unresolved
rows rather than inventing member references. Keep compatibility while consumers
migrate; gate provisional writes. Add meaningful model and migration tests.
```

### Phase 2 — Effective membership queries and general search

```text
Migrate membership consumers to effective polymorphic associations. Preserve
Account-based permission semantics while supporting provisional profile context
in authorized roster and claim discovery. Update mine filters, member counts,
Identity serializers, group eligibility, visibility, and deletion checks.

Implement a scoped, paginated member_candidates endpoint across Account,
PlayerProfile, and CoachProfile with a normalized typed response. Group linked
profile matches with their Account and explain canonicalization. Exclude private,
archived, merged, or unauthorized candidates and mark existing memberships.

Create/update/end members using membership IDs through an explicit compatible
route transition. Enforce allowed types, permission checks, canonicalization under
lock, idempotency, and database uniqueness. Test stale selection during claims.
```

### Phase 3 — Atomic transfer on profile linking

```text
Implement OrganisationMembershipTransferService and invoke it through the shared
profile-linking boundary used by ClaimSubject#effect!. Audit every sanctioned
linking path: approved claims, invitation redemption/acceptance, direct linking,
backfills, and merges. Pending/rejected claims must not transfer memberships.

Link profile and transfer memberships in one transaction with a consistent lock
order. Preserve roles/statuses/dates and immutable source history. Consolidate
compatible duplicates under one effective Account membership. Flag incompatible
status/role/privilege conflicts for authorized review; never auto-unsuspend,
auto-approve, or use highest-role-wins. Unresolved profile rows must not confer
effective access after linkage.

Use unique constraints and bounded conflict retries for concurrent writes.
Make retries idempotent. Write transfer audit events and after-commit notifications.
Test duplicate profiles across organisations, suspended targets, historical periods,
owner conflicts, invitation paths, failed transactions, and concurrent approvals.
```

### Phase 4 — Join policy and membership requests

```text
Add Organisation membership_policy open/approval_required/closed. Default new
organisations to approval_required; backfill existing ones to open so rollout
preserves current joins. Allow only explicitly authorized policy editing.

Add OrganisationMembershipRequest with a database unique pending request per
organisation/Account and audited approve/reject/cancel transitions. Self-service
always derives Account from the authenticated user and grants only member role.
Reject joins/requests to archived organisations. Guard suspended/ended membership
reactivation explicitly. Make approval idempotent and concurrency-safe.

Add minimal authenticated organisation discovery without opening the manager
catalogue or roster. Preserve independent claim boundaries: a pending join request
or open membership is not proof of profile ownership.
```

### Phase 5 — Tree and detail page

```text
Refactor Organisations.tsx using wine_words_front_end/src/components/Regions.tsx
as the interaction reference. Reuse tree=1 and parent_organisation_id. Provide
linked names, separate expand buttons, logos/acronyms, type/status labels,
Expand/Collapse all, ancestor-preserving search, and Active/Archived/All filters.
Preserve detached nodes, arbitrary depth, keyboard access, and return state.

Rename OrganisationDetail.tsx to OrganisationDetails.tsx without changing
/organisations/:id. Add Overview, Members, Sub-organisations, Requests, and
Management tabs with URL persistence and capability-aware rendering.

Extract and reuse existing forms/roster/actions. Support mixed member types,
membership-ID writes, general member search, and canonical Account rows with
linked profile references. Lazy-load tab data; handle invalid IDs, stale responses,
403/404, partial upload success, deletion conflicts, empty states, and mobile UI.
```

### Phase 6 — Organisation links and Identity self-service

```text
Create a shared OrganisationMembershipLinks component for PlayerDetail,
CoachDetail, AccountDetail, and the user's Account page. Unlinked profiles show
direct memberships; linked profiles show effective Account memberships labelled
Through linked Account. Preserve role/status/origin and separate history/conflicts.
Provide compact permitted organisation summaries on Players and Coaches lists
without N+1 requests. Link only readable destinations.

Extend Identity's existing membership section with discovery, Join, Request
membership, pending request cancellation, decisions/history, and transfer notices.
Derive actions from server capabilities; refresh account context after claims,
invitation acceptance, joins, approvals, and transfers. Self-service cannot select
another Account/profile or privileged role. Include accessible loading/errors.
```

### Phase 7 — Integration verification and rollout

```text
Run the relevant existing frontend and Rails tests and add integration coverage
for this plan's scenarios. Verify all Account-only query assumptions were migrated,
privacy/permission boundaries still hold, and membership history survives transfer.

Exercise production-like backfill data, duplicate/nullable legacy rows, concurrent
joins and claims, unique indexes, idempotent repair jobs, and route compatibility.
Check the complete flow: tree -> details -> typed member search -> add unclaimed
profile -> approved claim/invitation -> Account membership -> linked organisation
panels -> Identity join request -> authorized approval.

Run repository lint/type/build checks and relevant API checks. Report verified
behaviour, outstanding conflicts, rollout flags, and recovery constraints. Do not
remove compatibility columns/routes until discrepancy reports and callers permit it.
```

## 13. Acceptance scenarios

| Scenario | Expected result |
| --- | --- |
| Manager expands a federation | Its children appear; name click navigates independently |
| Active child has archived parent hidden by filter | Child remains visible with available parent context |
| Manager adds unclaimed player or coach | Profile appears as a provisional member with its type |
| Manager selects a linked profile | Backend stores Account membership and explains normalization |
| Account claims player in Club A and coach in Club B | Both organisation memberships belong to Account; both profiles remain |
| Two claimed profiles belong to the same organisation | One effective Account member; source history survives |
| Target Account is suspended in organisation | Claim does not unsuspend it; transfer requires review |
| Profile only has ended membership | History transfers; no active membership is granted |
| Transfer write fails | Claim/linking and all membership writes roll back together |
| Business transfer conflict is recorded | Claim may finish; unresolved profile membership grants no access |
| Retry or simultaneous linking/addition | No duplicate effective membership or audit operation |
| Identity user joins open organisation | Own Account becomes ordinary member subject to existing-state rules |
| Identity user requests approval-required organisation | Pending request; no active membership until authorised approval |
| Ordinary user views own organisation | Overview available when allowed; restricted roster explained clearly |
| User searches another person's private profile/account | Scoped search and direct-write authorization prevent disclosure/addition |
| Player/Coach/Account detail opens | Permitted organisation links show direct/effective origin and status |
| Source profile is merged or archived | Membership provenance and conflicts remain resolvable |

## 14. Completion criteria

- Clean accessible organisation tree and enriched existing detail route.
- All three supported member types work with canonicalization and scoped search.
- Successful claims and invitations atomically transfer memberships without losing history or granting implicit privileges.
- Duplicate/conflicting memberships have deterministic consolidation or review outcomes.
- Players, Coaches, Accounts, and Identity display correct effective organisation links.
- Users can join or request membership according to organisation policy, with review/cancellation support.
- Existing membership, claim, group eligibility, privacy, and deletion rules remain correct after query migration.
- Migration reports, relevant tests, rollout flags, and recovery procedures are complete before compatibility removal.
