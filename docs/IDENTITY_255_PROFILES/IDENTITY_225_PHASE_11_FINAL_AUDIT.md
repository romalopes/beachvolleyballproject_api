# Issue 225 — Phase 11: Final integration and security audit

**Status:** Complete for the local implementation and test/development databases. Full backend/frontend suites, static checks, migration status, read-only readiness, and rollback-only profile-merge diagnostics passed. Production-shaped backup restore and deployment remain Phase 12 gates. Depends on Phases 0–10. This maps to issue 225's Prompt 11 and 33-invariant checklist.

## Objective

Verify the shipped repository, not earlier reports, against the agreed identity invariants and all supported claim/invitation journeys.

## Invariant groups

1. **Cardinality:** every Account has exactly one Person; each Person has at most one Account; People may have many player and coach profiles; profiles may be unassigned.
2. **Ownership and authorization:** creator attribution is server-assigned; Coaches act only on owned profiles; organization/coach eligibility and staff review are backend-enforced.
3. **Claims and invitations:** linking is transactional; one-time tokens are digested, expiring, revocable, and race-safe; verified matching emails connect to the intended Person; rejected/accepted history remains auditable.
4. **Historical integrity:** training, tournament, assessment, ranking, memberships, and audit records survive profile linking and merge; deletion blocks while protected references exist.
5. **Compatibility and privacy:** role behavior is preserved; API and UI expose only authorized profiles/People; no stale single-profile assumptions or unsafe legacy endpoint remains.

## Audit work

- Search the complete repository for singular profile assumptions, old invitation/claim tables and endpoints, `/people` callers, creator User/Account mismatch, and direct profile/person assignments.
- Inspect schema constraints and migration ordering against real non-empty data scenarios.
- Walk through existing account claim, new signup, coach invite, manually shared invite, pending review, multiple profiles, profile merge, blocked deletion, and migration recovery.
- Record actual commands, results, known skips, failures, and limitations.

## Acceptance criteria

- Every invariant is marked verified with evidence, not merely assumed from code comments.
- Every failure has a fix or an explicitly accepted blocker and owner.
- Test and build results come from the final implementation state.
- A final report lists schema/API/UI changes, data migration status, residual debt, and rollout readiness.

## Checks

Run the full Rails suite, frontend suite, RuboCop, ESLint, TypeScript checks, frontend production build, and migration status/rehearsal as applicable. No production mutation is allowed in this audit.

## Implementation record

Reconciled invitation behavior across the unified API, compatibility routes, and frontend. Legacy Person-account invitation tokens still redeem through the verified-email service; legacy player invitation tokens still create review requests. New invitations use the unified table. Claim candidate discovery uses organization/current-coach policy, current visibility, and suppresses both migrated and legacy-form pending claims.

### Final verification run (2026-10-06)

- `bin/rails test`: **1,429 runs, 5,796 assertions, 0 failures, 0 errors, 1 skip**.
- Focused identity/compatibility/controller/integration set: **146 runs, 562 assertions, 0 failures, 0 errors**.
- `npm test -- --run`: **79 files, 878 tests passed**.
- `npm run lint`: passed.
- `npm run build` (includes `tsc -b`): passed. Vite reports the existing large-chunk warning (885.53 kB minified JS).
- Scoped RuboCop on 29 changed Ruby files (excluding generated `db/schema.rb`): no offenses.
- `git diff --check`: passed in frontend and backend worktrees.
- Test and development databases have all **17/17** required migrations through `20261006100006` applied.
- Read-only `IdentityProductionReadinessReport` on development: **0 blockers, 0 orphans**, 17/17 required migrations. It reports two duplicate canonical email groups and one duplicate canonical name group as warnings; no automatic merge was performed.
- Development reconciliation `20261006100004` verified no unresolved issuers, claimants, or token-to-subject mismatches. It repaired two missing `used_by_id` values through retained legacy player invitations. Source invitation rows were preserved.
- Rollback-only development diagnostics verified player and coach merges moved every populated direct reference type (assessments, training participants, player-coach links, and coach attribution in assessment sessions), retained source/audit rows, and rejected overlapping coaching periods. The development database has no assessment-session participants or ranking rows. Each diagnostic transaction rolled back all created/updated domain data.
- A concurrent test-database diagnostic submitted two merges for the same source/canonical pair; exactly one created an audit and the other was rejected after observing the archived source. Temporary profiles, merge audit, and the creator's diagnostic placeholder Account/Person were removed; the fixture User was preserved.
- A rollback-only development diagnostic verified `ProfileDeletionBlocker` permits deletion of a profile with no references and that an organisation membership both appears in the domain-language blocker list and prevents Person deletion. The diagnostic transaction rolled back all created/updated domain data.
- A concurrent development diagnostic raced profile deletion against a training participant insert. Deletion won, the foreign-key-protected participant insert was rejected, and no orphan remained; temporary records were removed.

### Earlier intermediate failures

An earlier run of the same full suites had failures because existing assertions encoded prior invitation-delivery, claim-discovery, hard-delete, creator-account, and UI behavior, and because compatibility tests queried legacy tables after new writes had moved to `claim_invitations`. Those assertions were aligned to the accepted contracts; the full suites above were rerun and passed. No production mutation was performed.

### Residual limitations

- The existing suite does not automate concurrent profile-merge/delete races. Local diagnostics verify one-winner concurrent merge behavior, delete-versus-reference safety, all populated merge reference types, overlap refusal, unused-profile deletion, and the organisation-membership deletion block. Production-shaped migration/merge rehearsal remains part of Phase 12.
- The development readiness report has three duplicate identity warnings requiring human review. They are not blockers and were not merged.
- Production was not mutated. Target confirmation, a restorable backup, baseline schema reconciliation, deployment host configuration, rehearsal on a restored production-shaped copy, and post-deploy evidence remain unverified in [Phase 12](IDENTITY_225_PHASE_12_PRODUCTION_ROLLOUT.md).
