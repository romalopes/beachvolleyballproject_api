# Identity Phase 7: Person consolidation

## Status

Planned. Design and implementation will be refined against the live models and references before migrations are written.

## Goal

Provide an explicit, authorized, transactional operation that marks a duplicate Person as merged into a canonical Person without deleting either identity or its historical records.

## Required behavior

- Record source, canonical target, actor, time, and an auditable outcome.
- Repoint eligible Person relationships while preserving PlayerProfiles and CoachProfiles as separate records.
- Preserve assessments, training participation, coaching periods, organisation memberships, and group memberships.
- Do not automatically merge Accounts, PlayerProfiles, CoachProfiles, or fuzzy name candidates.
- Detect conflicts and return a preview/result before performing any irreversible relationship change.
- Prevent self-merge, merged target/source misuse, cycles, and concurrent duplicate operations.

## Acceptance checks

- Only authorized administrators can preview and execute.
- A successful merge is atomic and leaves the source Person queryable with a canonical pointer.
- Account and membership conflicts are surfaced rather than silently resolved.
- Audits and historical IDs remain available.
- Tests cover authorization, idempotency/replay, conflicts, rollback, cycles, and retained history.

## Dependencies

Phase 8 defines detailed Account and duplicate-membership conflict handling. Phase 10 protects assessment history; Phase 13 audits the complete workflow; Phase 14 owns production rollout.
