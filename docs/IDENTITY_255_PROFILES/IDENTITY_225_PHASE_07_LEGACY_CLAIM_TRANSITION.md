# Issue 225 — Phase 7: Legacy claim and invitation transition

**Status:** Compatibility transition implemented; forward-reconciliation migrations are applied to local test and development databases. Development contained legacy invitation rows, and readiness moved from two missing used-invitation actors to zero blockers after reconciliation. Physical table retirement still requires a usage/retention decision. Depends on Phase 6's invitation contract.

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

## Implementation record

- New invitations from both compatibility URL families use the unified `claim_invitations` table. The Person account endpoint also accepts old `person_account_invitations` tokens during the compatibility period and redeems them through the legacy verified-email service. The player endpoint accepts old `player_claim_invitations` tokens as review requests; those legacy tokens never directly attach a profile. Existing raw tokens continue to be returned only at creation.
- Added forward migration `20261006100004_reconcile_legacy_claim_invitations` rather than changing the already-applied Phase 18 backfill migration. It repairs missing player invitation copies, fills recoverable `used_by_id` audit actors, and preserves both legacy source tables and rows. Its pre-production source also permits one email on distinct subjects; the local database had already applied the earlier version with no legacy rows, and production has not run it.
- Added `20261006100005_allow_multiple_active_claim_invitees` to remove global recipient uniqueness. The database still enforces one active invitation per claimable subject.
- Before writing, it rejects unresolved issuers, used invitations whose claimant cannot be mapped to a User, and a token digest already assigned to a different subject. One recipient email may have active invitations to different claimable subjects; the one-active-invitation invariant is scoped to each subject.
- Person invitation redemption uses the same verified-email rule whether its token is unified or legacy. Player/coach profile invitations link only when a verified User email exactly matches the invitation recipient; open links create review requests.
- Legacy models and tables are intentionally retained for the compatibility window. We have no endpoint-usage evidence or executed data reconciliation yet, so physical table removal is not authorized by this phase record.

Migrations `20261006100004`–`00006` are applied on both local test and development databases. Development had three legacy player-invitation rows; two corresponding used unified invitations lacked actors, and both legacy claimant Persons had linked Accounts. After migration, the readiness report showed 17/17 required migrations applied, zero blockers, and zero orphans. No invitation rows were inserted because the unified copies already existed; the recoverable actor gaps were reconciled. Legacy source tables and rows remain intact. Development still reports two duplicate-email groups and one duplicate-name group for human review. Production-shaped backup restore and migration rehearsal remain Phase 12 gates.
