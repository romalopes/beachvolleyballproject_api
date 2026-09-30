# Organisation, Group and Membership Plan

> **Status: Phases 1–3 implemented; Phase 4 data and API layers implemented, SPA
> and the development migration outstanding.**
>
> This file is the ground truth for the §-numbered design. It exists because the
> repository already contains four *unrelated* things called "Phase 4" — the
> Assessment, Sessions, Definitions and Ranking work each used that label — and
> because the section numbering below is referenced from model and controller
> comments that have no other way to point at a design.

## 1. Scope

A hierarchical organisational context — international federation, national body,
state association, club, academy — plus the people and squads that sit inside it,
and the rules for who may see and change each of those.

## 2. Design rules

These are the load-bearing decisions. Everything else follows from them.

### 2.1 The hierarchy is data, not schema
One self-referencing table (`organisations.parent_organisation_id`), never a table
per level. Depth is unbounded; no code may branch on `organisation_type` to decide
behaviour. A club and an academy behave identically, and a new type needs no
migration.

### 2.2 `Person`, not `User`
Organisation membership is keyed on `Person`, never on `User` or on a player
profile. A club must be able to record the people who are genuinely part of it — a
committee member, a parent, a volunteer coach — and not only those who signed up.

### 2.3 The hierarchy grants nothing
Being *above* an organisation in the tree is not the same as being *in* it. A
national federation member does not thereby see a club's private records. Every
visibility rule is an exact-match test on shared membership, never an ancestor test.

### 2.4 Archive, not delete
Retiring an organisation sets `status: "archived"`. It keeps its place in the tree,
its history stays queryable, and nothing is silently re-parented. The single
exception is §9.

### 2.5 Memberships are never deleted
Memberships are ended, never destroyed. A historical assessment must remain
explicable by the membership that existed when it was recorded.

### 2.6 Ownership has exactly one source of truth
`OrganisationMembership#role == "owner"` decides who owns an organisation.
`organisations.created_by_person_id` is **audit only** — who recorded the row — and
is never consulted for authority. Two answers to "who runs this club" is how a
transferred club ends up unmanageable by anyone.

## 3. `Organisation`

| Column | Notes |
| --- | --- |
| `parent_organisation_id` | self-reference; cycle prevention in the model |
| `name` | unique case-insensitively |
| `slug` | unique |
| `organisation_type` | free-form; never load-bearing (§2.1) |
| `description` | |
| `status` | `active` / `archived`, check-constrained |
| `created_by_person_id` | audit only (§2.6) |
| `logo` | Active Storage, one attachment |

Archive and restore are lifecycle transitions, not deletion (§2.4). Depth,
`ancestors` and `descendants` are computed with a recursive CTE carrying an explicit
depth column, because a CTE's row order is not guaranteed and "nearest first" is the
order a tree walk needs.

## 4. `OrganisationMembership`

| Column | Notes |
| --- | --- |
| `organisation_id` | |
| `person_id` | never `user_id` or `player_profile_id` (§2.2) |
| `role` | `owner` / `administrator` / `coach` / `member` |
| `status` | `pending` / `active` / `suspended` / `ended` |
| `joined_at` | stamped when the membership becomes active |
| `left_at` | stamped when it ends |

Roles and statuses are check-constrained in the database, so a rule that holds only
in tests is impossible.

### 4.1 Role is not volleyball role
`role` describes what a person does *for this organisation*. It is never derived
from the Person's own roles: a national coach can be an ordinary `member` of one
club and the `owner` of an academy.

### 4.2 `coach` is not a grant
Only `owner` and `administrator` may change who belongs to an organisation. A coach
coaches; that is not authority over the roster.

### 4.3 One active owner
At most one `owner` membership with `status: "active"` per organisation, enforced by
a **partial unique index** rather than only a validation — this is the one rule
where a race would otherwise leave an organisation with two owners and no way to
choose between them.

## 5. Lifecycle (§7)

`pending` → `active` → `suspended` → `ended`, plus `pending → ended`.

**A new membership defaults to `active`.** It used to default to `pending`, on the
principle that "adding somebody to a roster is an invitation, and an invitation is
not a grant". That principle was sound and the system could not honour it: there is
no acceptance endpoint, no inbox, and no channel at all by which an accountless
person could respond. So `pending` was an inert state only an officer could clear,
requiring a second call, and a pending row could sit between a club and being
deletable.

Recording somebody on your own roster is a record-keeping act, not a request, so it
now takes effect immediately. `pending` survives only as an explicit choice meaning
*recorded, not yet active* — somebody put on a roster ahead of time.

If real invitations are wanted later that needs an acceptance flow, a delivery
channel, and a product decision about accountless people. It should be added as a new
verb, not by reviving the old default.


## 6. Authorization

| Action | Who |
| --- | --- |
| Read | any training manager |
| Create | admin |
| Re-parent | admin |
| Update / archive / restore / logo | admin, curator, current owner, administrator, or the **creator while still a member** |
| Membership changes | the organisation's owner and administrators, plus admin |
| Hard delete | admin, and only under §9 |

Creating a node and moving one are claims made *to other clubs* about the tree, so
they are site-level. Editing the record is the club's own business.

### 6.1 The creator grant expires
`created_by_person` is a `Person` and is never cleared, so keying authority on it
alone would let a founder who resigned keep renaming the club forever while their
roster rights had correctly lapsed. The creator grant is therefore conditional on
holding an **active membership**. Owner and administrator grants expire with the
membership too.

### 6.2 Being on the roster is not authority over it
An ordinary member may read the organisation but may not change its record or its
membership.

## 7. Player visibility (§15)

A player is visible to anyone who is an active member of the **same** organisation.
This is what a roster is *for*: otherwise a club's players would have to be restated
as a list of coach-to-player grants, which drifts out of date the moment somebody
joins or leaves.

`PlayerProfile.visible_to` (the list) and `#visible_to_user?` (the single record)
implement the same rule and are pinned to agree by a test. Both keep `shared`
profiles visible to everyone, and both remain an *addition* to the existing rules,
never a replacement for them.

## 8. API

```
GET    /api/v1/organisations
POST   /api/v1/organisations                         admin
GET    /api/v1/organisations/:id
PATCH  /api/v1/organisations/:id                     editor
DELETE /api/v1/organisations/:id                     admin, §9 only
POST   /api/v1/organisations/:id/archive             editor
POST   /api/v1/organisations/:id/restore             editor
POST   /api/v1/organisations/:id/logo                editor, multipart
GET    /api/v1/organisations/:id/members
POST   /api/v1/organisations/:id/members             manager
PATCH  /api/v1/organisations/:id/members/:person_id  manager
DELETE /api/v1/organisations/:id/members/:person_id  manager (ends, never destroys)
```

Every serialised organisation carries `can_edit` and `can_delete`. The SPA gates on
these rather than re-deriving permissions from the user's role, because "may edit"
varies per organisation.

## 9. Hard delete

Archive (§2.4) is the way to retire an organisation. A hard delete exists only to
remove a **mistake** — a club created twice, a placeholder never used — and only
when the organisation has **no children** and **no memberships, not even ended
ones**.

The membership condition is what makes "a mistake" a fact rather than an opinion: a
leaf club with real members is a real club, and deleting it would cascade through
`organisation_memberships` and destroy the record that makes old assessments
explicable. A genuine club is therefore never deletable.

Refusals are `409`, not `422` — the request was well formed, the state is what
conflicts. `child_organisations` being `restrict_with_error` remains the
race-condition backstop behind the explicit check.

## 10. Phase 4 — GroupMembership (data + API done; SPA pending)

**Decided: a Group is "a group of people who share an Organisation."** The *members*
share an organisation; `Group` gets **no** `organisation_id`.

What Phase 4 had to fix, and what turned out to be missing from this list originally:

- `group_memberships.player_profile_id` became `person_id` (§2.2). The backfill is a
  lossless 1:1 join because `player_profiles.person_id` is `NOT NULL` and uniquely
  indexed — one profile is exactly one person, so the new unique
  `(group_id, person_id)` index is satisfied without collision handling.
- **`group_memberships` had no `role` and no `status` column at all.** This is why
  the work was larger than the three bullets used to suggest: §2.6's "ownership has
  exactly one source of truth" had nowhere to live, and §2.5's "memberships are
  ended, never destroyed" was not *representable* — it only held by accident. Both
  now mirror `organisation_memberships`, including the single-active-owner partial
  unique index and the `left_at`-only-when-`ended` check.
- `Group#owner?` read `created_by_id`, a second competing source of ownership
  against §2.6. It now reads the active owner membership. `created_by` remains, but
  as audit only, and visibility still keys off it because "private to its creator"
  is presentation rather than authority.
- `groups` still has no organisation link, by the decision above.

**The migration order is load-bearing, and the rehearsal proved why.** The
`person_id` swap has to run *before* the ownership backfill, because the only group
in the development data was created by somebody who had no player profile at all —
under a `player_profile_id` key they could not have been given an owner membership,
so a single "promote the creator's row" backfill would have left that group with no
owner and nothing able to manage it. Person-keyed membership is what makes the
second backfill pass (insert an owner row for a creator who is not on the roster)
possible. Both passes are counted and reported by the migration.

`status` is deliberately narrower than `organisation_memberships`' (no `pending`, no
`suspended`): a squad roster has no use for them yet, and a check constraint is
cheap to widen when there is a reason to. The old model comment rejecting an
invited/confirmed/attended vocabulary still stands — attendance is evidence about
one session, so it lives on the session, not the roster. Leaving a squad does not.

**Open for Phase 5:** without an `organisation_id` on `Group`, Phase 5 cannot name
*which* organisation an assessment session belongs to. It has to come from the
session itself rather than be inferred from the group — the development data's one
group has members spread across four organisations, so inference is not an option
even in principle.

## 11. Phase 5 — Assessment and Training context (not started)

The specification says `assessments.organisation_id / group_id`, but
`assessment_sessions` is the actual batch context and already carries `group_id`;
`assessments` has no group column. Recommendation: put the context on
`assessment_sessions` and resolve the organisation through the group.

`training_sessions` has neither, plus a `visibility` of `shared` / `private`. Those
existing values are preserved rather than renamed — renaming is a migration with no
benefit at this stage.

## 12. Phase 6 — Tournaments (not started)

A new domain rather than an extension. Minimum schema, curator/owner permissions,
visibility, eligibility and registration rules are to be designed before any code.

## 13. Known issues

- `db/seeds.rb` aborts on a second run: `VideoTag` uniqueness at the Video Tags
  block. Pre-existing and unrelated to this work, but it means `db:seed` is not
  currently re-runnable.
- The seed attaches `test/fixtures/files/sample.png` as a club logo. Replace with a
  real development asset or remove it.
- Production Active Storage (Supabase S3) is unverified: credentials, bucket, proxy
  protocol and URL generation.


### 4.4 One row per person per organisation
Unique on `(organisation_id, person_id)`. Re-joining after an ended membership
reactivates the same row, so the first stint's history is preserved.

### 4.5 Lifecycle timestamps follow the status
`left_at` belongs to `ended` and to nothing else, so the two can never disagree
about whether somebody actually left. Mirrored by a database check.
