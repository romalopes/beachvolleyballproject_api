# Issue 225 — Phase 12: Production migration and rollout

**Status:** Blocked. Separate operational work after Phase 11; not part of feature implementation.

## Objective

Deploy reviewed schema/application changes to the confirmed production target with a verified recovery path and evidence that identity and history invariants hold before and after rollout.

## Existing blocker

[Identity Phase 14](IDENTITY_PHASE_14_PRODUCTION_MIGRATION.md) records a read-only preflight blocker: the intended live target is unconfirmed, required baseline schema including `player_coaches` is missing at the configured target, no verified restorable backup was found under the active backup prefix, and the checked-in Kamal host/registry values are placeholders. Resolve and re-document those facts before scheduling production work.

## Preconditions

- Confirm the production database and deployment target with the release owner.
- Create a fresh encrypted backup, record checksum/location, and prove restore to a disposable database.
- Reconcile missing baseline schema and run the readiness report with a read-only role.
- Rehearse the exact release/migrations on a production-shaped restored copy; measure locks and duration.
- Obtain operator approval and schedule a maintenance window.

## Rollout sequence

1. Capture pre-migration readiness JSON and row/preservation counts.
2. Deploy the reviewed release and run migrations once using the documented runner/order.
3. Confirm all migrations are up and health checks pass.
4. Capture post-migration readiness JSON; require zero blockers/orphans and explain every count difference.
5. Run non-mutating smoke reads for health, `/me`, profile visibility, and claim/invitation status.
6. Monitor errors and locks through the agreed observation window; retain release, backup, reports, and sign-off records.

## Recovery

Prefer a forward fix after schema/data writes. Restore a backup only through the recovery owner because writes after the backup would be lost. Do not manually edit `schema_migrations`, run unreviewed rollbacks, merge People, or delete profiles as incident response.

## Acceptance criteria

Target and backup are verified; rehearsal succeeds; migration completes; post-report blockers and orphan counts are zero; preserved domain counts reconcile; smoke checks pass; recovery owner signs off. Until then, this phase remains blocked and the feature must not be described as production-ready.
