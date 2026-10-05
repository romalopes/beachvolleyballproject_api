# Issue 225 — Phase 4: Profile merge and archive lifecycle

**Status:** Implemented; schema is applied to local test and development databases. Archive/restore is covered by the backend suite. Rollback/cleanup diagnostics verified movement for every populated direct reference type, audit creation, source retention, rejection of overlapping coaching periods, and one-winner behavior for simultaneous merge attempts. Automated race coverage remains absent. Depends on Phase 0 and the Phase 3 policy/reference audit.

## Objective

Provide an explicit, auditable operation for profiles proven to be duplicates. A Person having multiple profiles is allowed by the target model and is not, on its own, evidence of duplication.

## Design work

Before schema changes, inventory all foreign keys and polymorphic references for each profile type. Classify each reference as historical, mutable relationship, audit record, or safely movable. Determine which fields are copied to the canonical profile and how conflicting profile attributes are resolved. Merges must be same profile type; define whether different Person ownership is allowed and what explicit authorization/confirmation it requires.

## Implementation outline

- Add merge provenance: canonical profile reference, merged timestamp, actor, reason, and archival state/time.
- Add a transaction-backed `ProfileMergeService` that locks source and canonical profiles in a stable order, validates eligibility, moves only approved references, records an immutable audit, and marks the source merged/archived.
- Reject self-merges, cycles, already-merged sources, incompatible profile kinds, and unsafe reference conflicts.
- Keep the source profile row; historical IDs must remain resolvable.
- Ensure normal profile linking never calls this merge service implicitly.

## Acceptance criteria

- Merge is atomic, authorized, auditable, and safe to retry or reject.
- Every moved reference resolves to the intended canonical profile; protected history is retained.
- Multiple legitimate profiles on one Person remain separate unless explicitly merged.

## Verification

For every inventoried association, test move, preserve, or block behavior. Test concurrent merge attempts, cycles, conflicting owners, already-merged rows, and audit completeness. Rehearse migration/backfill on representative data before enabling the operation.

## Implementation record

Added `ProfileMerge`, merge provenance columns, `ProfileMergeService`, and Admin/Curator `POST /players/:id/merge` and `/coaches/:id/merge` operations. Sources remain archived rows. Direct profile references are reassigned only after collision checks; JSON ranking snapshots keep their original IDs and the source row remains resolvable. Merges require both profiles to be the same type and already linked to the same Person or both unlinked; claims on either profile must be resolved first. Active source invitations are revoked. Migration `20261006100003_add_profile_merge_audit` is applied to test and development databases. Rollback-only diagnostics moved assessments, training participants, coaching relationships, and assessment-session coach references; they verified audit/source retention and rejected inclusive overlapping PlayerCoach periods. The development dataset has no assessment-session participants or ranking rows. A concurrent test-database diagnostic confirmed that two attempts against the same profiles produce one merge audit and one rejection; all temporary rows were cleaned up. Automated concurrent merge coverage remains absent.

Ordinary archive/restore transitions now maintain `archived_at`; archiving revokes unexpired claim invitations (and expires stale ones), while restore clears the timestamp for non-merged profiles. Merge archives retain their merge timestamps and actor.

Migration `20261006100006_revoke_archived_profile_invitations` applies the same invalidation rule to already-archived profiles during rollout. It is applied to test and development databases; the development dataset had no active invitations against archived profiles to update.
