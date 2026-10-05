# Issue 225 — Phase 0 repository audit findings

**Audited:** 2026-10-05 against the current workspace in `beachvolleyballproject_api` and `beachvolleyballproject`.

## Current relationship model

```text
User (authentication) 0..1 Account 1..1 Person
                                  Person 0..N PlayerProfiles
                                  Person 0..N CoachProfiles
```

- `accounts.user_id` and `accounts.person_id` have unique indexes. `accounts.person_id` is nullable in `db/schema.rb`; `Account#ensure_person` builds a Person before validation when an Account is saved without one. User registration itself does not create an Account (`app/controllers/api/v1/registrations_controller.rb`). Preserve accountless Users; Phase 1 concerns persisted Accounts.
- `Person` has `has_many :player_profiles` and `has_many :coach_profiles`; singular first-profile compatibility readers remain. The API summary emits both singular convenience IDs and plural ID lists.
- Both profile `person_id` columns are nullable. A personless PlayerProfile and CoachProfile require a display name. `created_by_id` on each profile references `users`, not Accounts.
- People remains an intentional catalogue: `/people`, `People.tsx`, and `PersonCreatePanel` support recording known People and choosing a placeholder profile path. Keep those capabilities.

## Claim and invitation state

- `ClaimInvitation` is polymorphic across `PlayerProfile`, `CoachProfile`, and `Person`; `ClaimSubject` implements eligibility and link effects for all three.
- `PlayerClaim` stores a polymorphic subject and retains a compatibility `player_profile_id` column. `player_claims_single_subject` enforces exactly one representation.
- Legacy `PlayerClaimInvitation` and `PersonAccountInvitation` models/routes still exist. Phase 18 backfills both into `claim_invitations`; the Phase 18 document says legacy endpoints/tables remain for one release.
- `ClaimInvitationService` currently auto-links only when `ClaimInvitation#delivered_to?` passes (email is present, mail delivery was recorded, and the User email is verified/matches). A manually copied link becomes a pending claim. This conflicts with the later product decision that a verified matching address is sufficient; Phase 6 must change that gate.
- Account linking transfers a signup-only empty placeholder Person and marks it merged. `ClaimSubject` retires the placeholder before updating the Account to avoid a cached inverse reverting the re-point. Preserve this fix and verify its audit semantics.

## Profile reference inventory

### PlayerProfile direct references

- `assessments.player_profile_id`
- `training_session_participants.player_profile_id`
- `assessment_session_participants.player_profile_id`
- `player_coaches.player_profile_id` (current and ended periods)
- `ranking_consolidation_rows.player_profile_id`
- `player_claims` polymorphic subject; compatibility column may be null for a PlayerProfile subject
- `claim_invitations` polymorphic subject
- Legacy `player_claim_invitations.player_profile_id`
- `ranking_consolidation_sessions.ranking_snapshot` JSON contains profile IDs; update/retention behavior needs review before merge/delete

Group membership is keyed by Person after migration `20260930050001`; it is not a direct profile FK. Other JSON snapshots and logs must be searched before any reference migration.

### CoachProfile direct references

- `assessments.coach_profile_id`
- `assessment_sessions.coach_profile_id`
- `player_coaches.coach_profile_id` (current and ended periods)
- `player_claims` and `claim_invitations` polymorphic subjects

Both profile models use restrictive associations for most historical links. PlayerProfile currently has `training_session_participants` with `dependent: :destroy`; this is unsafe for an exposed hard-delete action and must be removed/changed to restriction before deletion can be enabled.

Tournament and schedule references were not found by the initial schema search; confirm repository-wide, including JSON, ActiveStorage, and external integrations, before approving a merge/delete reference list.

## Authorization baseline

- Profile visibility and ownership currently use `created_by_id` User IDs.
- Player and coach visibility rules differ. PlayerProfile includes same-organisation visibility; CoachProfile currently uses shared-or-owner only.
- There is no central `ProfileClaimability` service. Candidate discovery, visibility, invitation, and claim paths have separate logic.
- Player/coach destroy routes are absent. Preserve this until Phase 5's reviewed guards exist.

## Singleton and API compatibility inventory

- Singular Person readers: `Person#player_profile`, `Person#coach_profile`, identity summary singular keys, inline participant resolution, API `/me` singular profile keys, and controllers selecting a profile for compatibility.
- Plural profile relations and ID arrays already exist. Treat singular outputs as compatibility conveniences; audit each call site before removing it.
- Frontend uses explicit profile lists in some identity/detail flows but also falls back to singular IDs in `PersonIdentityList`, `Identity`, `PlayerDetail`, and `CoachDetail`.
- PlayerCoach assessments and training sessions refer to profiles directly; a merge cannot update only Person links and assume all history follows.

## Keep/remove decision for this implementation

**Keep:** People UI/API, Person account invitations/linking, Person consolidation/audit, accountless player/coach placeholders, current API aliases during compatibility, and historical claim records.

**Change:** Account's database Person constraint; creator ownership representation; claimability authorization; Person invitation verified-email gate; profile merge/archive; hard-delete safety; dashboards and clear claim outcomes.

**Remove only after a compatibility window and data review:** duplicate legacy invitation tables/endpoints and truly unused singular readers/client methods. No current evidence authorizes deleting People or Person-claim behavior.

## Phase 14 production constraints

The Phase 14 document reports an unconfirmed configured production target, a missing `player_coaches` table, no verified restorable backup in the active prefix, and placeholder Kamal host/registry configuration. These are operational blockers; no production migration is authorized by this code implementation.

## Outstanding review items

- Validate all profile FKs and JSON snapshots against complete schema and application searches before Phase 4/5.
- Confirm Account callback validation/transaction behavior before making `accounts.person_id` non-null.
- Decide dual-field retirement timing after creator Account attribution is backfilled and deployed.
- Plan compatibility duration and retention for legacy invitations/claims.
