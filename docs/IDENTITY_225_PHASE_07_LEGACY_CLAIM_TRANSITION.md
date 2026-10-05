# Issue 225 — Phase 7: Legacy claim and invitation transition

**Status:** Planned. Depends on Phase 6's stable replacement API and invitation contract.

## Objective

Retire duplicate legacy endpoints and storage only after preserving claim, invitation, and review history. “Unified” behavior does not justify discarding records.

## Conversion policy

- Inventory all rows and their statuses before migration; retain privacy-safe before/after counts.
- Backfill legacy player invitations to the unified profile subject only when the target profile is known and unambiguous.
- Revoke active obsolete tokens as part of a reviewed transition so old links cannot grant access after cutover.
- Preserve Person account invitations and Person claims because the later product requirement keeps known-Person linking. If tables are eventually consolidated, retain issuer, recipient, timestamps, outcome, and audit semantics.
- Never convert a Person subject into a player or coach profile based on a guess. Keep a legacy audit row or mark it revoked with a machine-readable reason and migration audit entry.
- Keep old endpoints read-only or compatible for the agreed window, then remove them only after client usage is checked.

## Acceptance criteria

- Every source row is accounted for as migrated, retained, or safely revoked; no unexplained count loss.
- Old active tokens cannot bypass the new policy.
- Pending claims remain visible to their authorized reviewers after migration.
- Rollback and forward-recovery behavior is documented before deployment.

## Verification

Use migration fixtures containing active, expired, revoked, used, pending, approved, and ambiguous records. Test on a copy containing realistic non-empty tables; an empty local test database is insufficient evidence for backfill correctness.
