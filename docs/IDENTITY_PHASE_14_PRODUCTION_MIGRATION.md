# Identity Phase 14: Production migration and validation

## Status

Planned. Local migrations do not constitute production readiness.

## Goal

Prepare safe production rollout and post-migration validation without automatically merging or deleting identity records.

## Required work

- Inspect production cardinalities, nulls, duplicates, membership conflicts, and orphaned references.
- Confirm backups and recovery path using the existing backup/restore runbook.
- Review migration reversibility, lock behavior, indexes, and deployment ordering.
- Provide a repeatable validation report for Person/Account/Profile cardinalities and preservation of assessment, organisation, group, and historical records.
- Record rollout, monitoring, and rollback steps.

## Acceptance checks

- No destructive data operation runs without explicit operational approval.
- Pre/post counts and relationship checks are recorded.
- Validation can be rerun and reports anomalies without modifying production data.

## Dependencies

Phases 7–13 must settle consolidation, conflict, API, and security behavior before production rollout instructions are finalized.
