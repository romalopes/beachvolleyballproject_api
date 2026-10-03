# Identity architecture audit (Phase 1)

## Scope

Read-only audit of the existing API, schema, models, controllers, and frontend references against the supplied identity plan. The target architecture is one canonical `Person` with an optional `Account` and multiple player and coach profiles.

## Current architecture

```text
Person 1 ── 0..1 Account
Person 1 ── 0..1 PlayerProfile (unique FK, required FK)
Person 1 ── 0..1 CoachProfile (unique FK, required FK)
Person 1 ── 0..many GroupMemberships
Person 1 ── 0..many OrganisationMemberships
```

`User` carries authentication and role assignments; `Account` joins a user to a person. Training participants, assessments, player-coach periods, and memberships refer to domain profiles or people, not directly to `Account`.

## Existing behavior found

- `Person` already exists and is decoupled from `User`/`Account`; it has provenance, aliases, active/archived/merged states, and a `merged_into_id` link.
- `Account.person_id` is nullable and uniquely indexed, enforcing at most one account per person.
- `PlayerProfile.person_id` and `CoachProfile.person_id` are both non-null, uniquely indexed, and validated unique in their models.
- `Person` has singular `has_one` profile associations. The identity summary returns singular IDs; multiple endpoints and permissions select `person.player_profile` / `coach_profile` implicitly.
- Player/coach create endpoints create or select a Person and nest profile data; edit endpoints prohibit re-pointing `person_id`.
- `PeopleController#promote` is admin-only and currently refuses to create a second profile of a kind.
- Player claiming, claim invitations, identity consolidation, and conflict-resolution workflows were not found. Existing duplicate finder only suggests candidate people. Merge state exists, but no consolidation service/API was found in this audit.
- Organisation and group memberships are keyed by Person. Groups may have a nullable organisation. Membership uniqueness is scoped to an organisation/group and person.
- Assessments reference PlayerProfile and CoachProfile IDs; training session participants and player-coach history also retain profile IDs. Consolidation must re-point these historical references transactionally if profile/person ownership changes.
- Frontend API types and people screens assume singular `player_profile_id` / `coach_profile_id`; player/coach lists render a person-backed profile. These need a follow-up compatibility migration before the UI can choose among many contexts.

## Required work and risks

1. Drop unique indexes and model validations for profile-to-person links; make player `person_id` nullable. Keep coach `person_id` required until a use case for unassigned coaches is designed.
2. Change Person associations to `has_many`, protect referenced profiles from accidental Person deletion, and provide plural identifiers in API responses while retaining legacy singular identifiers during transition.
3. Audit every implicit “current profile” lookup. A user's default coach/player profile is ambiguous once multiple profiles are allowed; APIs and UI need an explicit context selection rule.
4. Phase 3 implements claim storage and conflict behavior plus a standalone `display_name` required for unlinked profiles. Claim interaction screens remain for Phase 12.
5. Treat claims, invitations, and consolidation as audited, authorized transactions. Do not infer merges from names.
6. Keep all profile ID references and history intact during later consolidation; define duplicate membership behavior before migration.

## Phase status

Phase 1 audit is complete. The detailed, read-only findings above are based on repository code and schema, not assumptions from the plan. Phase 2 implementation is tracked in `IDENTITY_PHASE_02_CARDINALITY.md`, and Phase 3 in `IDENTITY_PHASE_03_PLAYER_CLAIM.md`; later workflows require their own design, implementation, and verification.
