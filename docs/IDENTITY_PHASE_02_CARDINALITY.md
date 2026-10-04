# Person and profile cardinality (Phase 2)

## Implemented

- `Person` now has many player profiles and many coach profiles.
- `PlayerProfile` permits an absent Person; `CoachProfile` still requires one because the existing coach workflow always creates/selects a Person and no unassigned-coach workflow exists.
- Profile `person_id` uniqueness validations were removed. Database indexes remain, but are no longer unique.
- Player `person_id` is nullable. Coach `person_id` remains non-null.
- Person deletion is restricted when profiles exist so deleting an identity cannot cascade into assessment, training, or coaching history.
- The people identity payload keeps the legacy singular profile IDs and also returns `player_profile_ids` and `coach_profile_ids`.
- Admin promotion can create an additional profile of either kind.

## Schema change

Migration `20261003000001` removes the unique profile/person indexes and makes the player foreign key nullable. It does not change Account cardinality, profile history foreign keys, or coach nullability.

## Compatibility and follow-up

Legacy singular profile fields remain additive compatibility fields; multi-profile UI and attribution selection are implemented in Phase 12. Phase 3 added a required `display_name` and API support for unlinked profiles. Claim, invitation, context-selection, and consolidation interfaces are now implemented in Phase 12.

## Verification

Migration execution succeeded against the configured PostgreSQL database. The full Rails suite passed: 1,319 tests, 5,242 assertions, 0 failures, 0 errors, 1 existing skip. Frontend tests passed: 850 tests across 76 files. `npm run build` passed; Vite reported its existing large-chunk advisory. Frontend changes are limited to accepting plural summary IDs as additive API fields, so existing screens continue to read the legacy keys.

## Follow-up phases

Phases 3–13 and 15 are implemented and documented. Phase 14's runbook and read-only readiness report are complete, but production migration remains blocked by its live operational prerequisites; see `IDENTITY_PHASE_14_PRODUCTION_MIGRATION.md` and the current phase index.
