# Issue 225 — Phase 11: Final integration and security audit

**Status:** Planned. Depends on Phases 0–10. This maps to issue 225's Prompt 11 and 33-invariant checklist.

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
