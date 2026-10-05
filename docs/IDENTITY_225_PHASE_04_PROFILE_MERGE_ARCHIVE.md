# Issue 225 — Phase 4: Profile merge and archive lifecycle

**Status:** Planned. Depends on Phase 0 and the Phase 3 policy/reference audit; Phase 4 must finish before hard-delete design in Phase 5.

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
