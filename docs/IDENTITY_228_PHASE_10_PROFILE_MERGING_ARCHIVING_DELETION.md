# Issue 228 — Phase 10: Profile merging, archiving and deletion

## Goal and scope

Provide an explicit, auditable way for an administrator or curator to combine duplicate player profiles or duplicate coach profiles. Keep the selected canonical profile, archive the source as a redirect, and preserve its history. Keep hard deletion narrowly limited to profiles with no protected dependencies. Claiming and invitation flows never merge records automatically.

Only same-type merges are supported. This phase does not merge Accounts or People, and it does not rewrite the Person association of either profile. Both profiles must have the same effective Account linkage (direct profile Account, otherwise its Person's Account); this permits two unlinked records while refusing a merge that would combine distinct Accounts or link an Account-owned record to an unowned one.

## Behavior implemented

- `ProfileMergeService` locks both same-type rows in stable ID order and rechecks that each remains active and unmerged before writing.
- Only admins and curators can merge. A nonblank reason is mandatory and retained in `profile_merges` with the actor, source, canonical target, timestamp, and per-reference counts.
- The canonical target must be active and distinct from the source. Pending claims on either record block the merge. Account ownership must match.
- Before moving references, the service detects same-session player participant collisions, duplicate ranking rows, and overlapping player/coach relationship periods. A conflict aborts the transaction without partial changes.
- Supported foreign-key references move to the canonical profile. The source row remains, is archived, and points to the canonical profile. Active invitations to the source are revoked (or marked expired when their expiry has passed).
- Profile detail pages expose the same-type merge workflow only to admins and curators. It requires selecting a target, entering a reason, and checking an explicit confirmation. A successful merge navigates to the canonical profile.
- A personless player profile can be edited from its detail page; the Edit action no longer depends on a Person association.
- Hard deletion checks direct Account ownership, Person Account ownership and group membership, profile history, claim/invitation records, merge audit/link rows, and the profile's Person siblings. A failed foreign-key delete caused by a concurrent reference is reported as protected history.

## Deletion dependency matrix

| Dependency or history | Player profile merge | Coach profile merge | Hard-delete behavior |
| --- | --- | --- | --- |
| Direct `account_id` / linked Person's Account | Both profiles must resolve to the same Account | Both profiles must resolve to the same Account | Blocks deletion if either the profile or its Person is Account-linked |
| `assessments.player_profile_id` / `assessments.coach_profile_id` | Repoint to canonical | Repoint to canonical | Blocks deletion |
| Training session participants | Repoint to canonical; same-session duplicate blocks merge | Not a coach-profile FK in the current schema | Blocks player deletion |
| Assessment session participants | Repoint to canonical; same-session duplicate blocks merge | Not a coach-profile FK in the current schema | Blocks player deletion |
| Assessment sessions | Not a player-profile FK in the current schema | Repoint coach FK to canonical | Blocks coach deletion |
| `player_coaches` relationships | Repoint player FK; overlapping periods for the same coach block merge | Repoint coach FK; overlapping periods for the same player block merge | Blocks deletion of either endpoint |
| Ranking consolidation rows | Repoint to canonical; duplicate row in one consolidation blocks merge | Not applicable | Blocks player deletion |
| Ranking snapshot JSON | Kept as historical evidence with the original profile ID | Not applicable | Blocks player deletion when a snapshot contains the profile ID |
| Claims and claim invitations | Source's active invitations are revoked; claims remain attached to source as history | Source's active invitations are revoked | Any claim or invitation reference blocks hard deletion |
| Legacy player claim invitations | Active source invitations are revoked | Not applicable | Blocks player deletion |
| Merge audit and redirect links | Audit records source and target; source is an archived redirect | Same | Any merge audit or merge link blocks hard deletion |
| Person group membership | Person association is unchanged | Person association is unchanged | Blocks deletion of a profile linked to a Person with group membership |
| Person organisation membership | Remains attached to retained Person; not transferred by a profile merge | Same | Profile deletion leaves Person and its memberships intact; they are not profile foreign keys |
| Tournaments and schedules | No direct profile foreign key was found in the current schema/model audit | No direct profile foreign key was found in the current schema/model audit | Database FK protection remains the final guard if such a reference exists outside the audited models |

The service moves only the listed, explicit foreign keys. JSON snapshots are not rewritten because they are historical evidence. The matrix reflects the schema and models in this repository at implementation time; add a row and a blocker before introducing a new direct profile reference.

## Files changed

- Backend: `app/services/profile_merge_service.rb`, `app/services/profile_deletion_blocker.rb`
- Backend tests: `test/services/profile_merge_service_test.rb`, player and coach controller tests
- Frontend: `src/api.ts`, `src/components/identity/ProfileMergePanel.tsx`, `src/pages/PlayerDetail.tsx`, `src/pages/CoachDetail.tsx`, `src/utils/people.ts`
- Frontend tests: `src/components/identity/ProfileMergePanel.test.tsx`

## Verification

- Rails: focused merge service plus player and coach controller suites — **101 tests, 367 assertions, 0 failures, 0 errors**.
- Frontend: merge panel, API, PlayerDetail, and CoachDetail suites — **4 files, 69 tests passed**.
- Frontend production build: passed. Vite reported the existing large-chunk advisory (the generated JS bundle is approximately 885 kB).
- Ruby syntax checks for the changed service and controller test files — passed.

## Operational notes

No migration is required; the `profile_merges` audit table and merge columns already exist. Hard deletion is intentionally unavailable whenever a profile has protected history. Archive remains the fallback lifecycle action. The merge action is irreversible through the UI, so staff must verify the target before confirming.
