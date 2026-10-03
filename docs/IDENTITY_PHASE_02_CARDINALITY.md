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

## Compatibility and remaining work

Legacy singular profile reads return the first associated profile while callers are migrated. That is a compatibility measure only; it is not a durable context-selection rule. Current frontend forms still work with the original one-profile flow, but do not yet let users select among multiple coach/player profiles. A player profile without a Person can be stored at the model/database layer, but current API creation and display flows do not provide a standalone name; Phase 3 must add an explicit claimable-profile design before relying on that capability.

## Verification

Migration execution succeeded against the configured PostgreSQL database. The full Rails suite passed: 1,319 tests, 5,242 assertions, 0 failures, 0 errors, 1 existing skip. Frontend tests passed: 850 tests across 76 files. `npm run build` passed; Vite reported its existing large-chunk advisory. Frontend changes are limited to accepting plural summary IDs as additive API fields, so existing screens continue to read the legacy keys.

## Follow-up phases

Phases 3–5 (claiming, candidate discovery, and secure invitations), 7–15 (consolidation, conflict handling, organisation/group validation, assessment regression, complete API/UI migration, security review, production rollout, and the full business integration matrix) are not implemented by this change. Phase 6's database/model cardinality is enabled here; explicit coach-context selection in API authorization and UI remains part of the API/UI follow-up. Do not treat these workflows as available until their implementation and phase-specific verification are complete.
