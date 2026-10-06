# Identity Phase 14: Production migration and validation

## Status

Implemented as a production runbook and a repeatable, database-enforced read-only readiness report. Production was queried read-only on 2026-10-04; no production migration, merge, or cleanup was performed.

## Read-only readiness report

Run the task against the intended database with the matching application release and a read-only database role:

```sh
RAILS_ENV=production bin/rails identity:production_readiness
```

The task opens a transaction and issues PostgreSQL `SET TRANSACTION READ ONLY` before querying. It prints JSON aggregate data only; it never emits names, emails, or record IDs. It exits nonzero when a blocker is found. Warnings (such as pending migrations, stale expired invitations, blank names on unlinked players, or possible duplicate Person email/name groups) are printed for operator review and do not get resolved automatically.

The output records:

- Whether all seventeen required identity/Issue 225 migrations through `20261006100006` are applied.
- Whether required baseline tables are present. A missing expected table is a blocker; its preservation count is `null` rather than causing the report to fail before emitting diagnostics.
- Row counts for Person, Account, PlayerProfile, CoachProfile, claim/invitation/consolidation, and organisation/group membership tables.
- Cardinalities: linked/unlinked rows, multiple profiles per Person, and possible duplicate canonical email/name groups. Multiple profiles and unlinked PlayerProfiles are valid outcomes and are reported as counts.
- Relationship-preservation counts for assessments, training/assessment participants, player-coach relationships, memberships, and aliases.
- Orphan counts for key identity, assessment, roster, membership, claim, invitation, and consolidation foreign keys.
- Blocking invariant violations and non-blocking warnings with remediation hints.

Run it before and after migration and retain both JSON reports in the change record. Compare all row/preservation counts; the identity schema migrations should not rewrite domain data. The report is safe to rerun. Warnings require human review, especially possible duplicates, and are not instructions to merge.

## Migration inventory and operational characteristics

| Migration | Change | Operational notes |
| --- | --- | --- |
| `20261003000001_allow_multiple_profiles_per_person` | Makes `player_profiles.person_id` nullable and replaces unique Person indexes on player/coach profiles with non-unique indexes. | `remove_index` / normal `add_index` operations take table locks and index builds block writes on the affected profile tables. No `CONCURRENTLY` option is used. Schedule a low-traffic maintenance window and allow migrations to finish before app health checks pass. |
| `20261003000002_create_player_claims` | Adds `display_name`, claim table, foreign keys, valid-status check, and a partial unique index for one pending claim per profile. | Schema-only; existing profile rows are not rewritten. The partial index build scans the new, empty table. |
| `20261003000003_require_person_for_coach_profiles` | Enforces non-null `coach_profiles.person_id`. | Preflight must report zero missing coach Persons. Existing app data is expected to satisfy this invariant. |
| `20261003000004_create_player_claim_invitations` | Adds invitation table, digest uniqueness, active-invitation partial unique index, foreign keys, and status check. | Schema-only. Raw tokens are never backfilled or stored. |
| `20261004000001_create_person_consolidations` | Adds merge provenance to people and creates the consolidation audit table. | Schema-only; it does not consolidate any Person records. |

These migrations use ordinary transactional Rails/PostgreSQL DDL, not concurrent index creation. Verify expected lock behavior against a production-sized restored copy before the window. Migration 1 has a material rollback limit: after the app creates multiple profiles for one Person, rolling it back would recreate unique indexes and fail (or require deleting valid identity data). After identity writes or consolidations begin, prefer a forward fix. Do not roll back the audit/claim/invitation tables after they contain records unless the recovery owner explicitly accepts losing those records.

## Production rollout procedure

### Before the window

1. Confirm the production provider and direct database URL. Use a read-only database role for the readiness report where available; do not paste credentials into logs or the change record.
2. Trigger the existing encrypted database backup workflow. Record the backup object key, checksum, provider, and timestamp. Confirm backup freshness and successful decryption/restore validation to a disposable database using [DATABASE_BACKUP_AND_RESTORE.md](DATABASE_BACKUP_AND_RESTORE.md).
3. Build the exact application release to be deployed and run the readiness task against production. Resolve blockers before deployment. Review every duplicate-email/name and profile warning manually; do not merge or delete identities as part of migration preflight.
4. Restore a recent backup to a disposable database and rehearse the migration plus post-check. Record migration duration and observed locks. Verify assessment, roster, membership, and alias counts are preserved.
5. Schedule low traffic. Announce the window and pause identity-changing administrative work. The app should remain on the old release until schema migration has completed.

### Deployment

The current `bin/docker-entrypoint` runs `bin/rails db:prepare` when the Rails server command starts. Kamal's current configuration has one web host, so the first new container startup applies pending migrations before starting the server; startup logs must be watched through this step. Do not separately run a concurrent migration process while that startup migration is active. If the deployment topology changes to multiple web hosts, revisit this ordering and use a single release migration runner before starting new web processes.

Deploy the reviewed release during the window. Monitor database connections, lock waits, migration logs, and the application health check. Do not enable identity writes or tell users the feature is live until all migrations are `up` and the new app reports healthy.

### After deployment

1. Run `RAILS_ENV=production bin/rails identity:production_readiness` again and save the JSON output. Confirm all required migration values are `true`, blocker count is zero, and all orphan counts are zero.
2. Compare pre/post `counts` and `preservation_counts`. Schema migrations in this phase should preserve row counts. Investigate every unexplained difference before resuming writes.
3. Run non-mutating smoke checks: health endpoint, authenticated `/api/v1/me`, and authorized profile/claim status reads. Do not create a real production claim or consolidate records as a smoke test.
4. Watch application/database logs and error rates through the agreed observation period. Record the release ID, migration versions, backup reference, pre/post report locations, elapsed time, warnings accepted, and operator sign-off.

## Stop and recovery procedure

- **Preflight blocker or rehearsal failure:** do not deploy. Correct the data or migration/release, then rerun the report and rehearsal.
- **Migration fails before app starts:** keep the old app active if possible. Inspect migration state and logs; do not manually edit `schema_migrations`. A transactional DDL migration should roll back its current migration, but verify before retrying.
- **New release fails after migrations:** first diagnose and prefer a forward-fix release. The migration changes the active schema, and rollback of Phase 2's unique profile index is unsafe after multiple profiles are created. Restore a pre-window backup only under the incident/recovery owner's approval because it discards all database writes made after the backup. Provision/restore to a new database, validate it, then switch the application connection; preserve Active Storage objects separately because the database backup does not contain them.
- Do not run `db:rollback`, manually drop tables/indexes, merge Persons, or delete duplicate memberships as an unreviewed deployment response.

## Evidence from the development rehearsal

The readiness task regression test passed (**1 test, 12 assertions**). The task was run against the configured development database in a transaction explicitly marked read-only. At that time, all five then-required migration versions were present, all reported orphan counts and blockers were zero, and the preservation counts were emitted. It reported two duplicate canonical-email groups and two duplicate canonical-name groups as review warnings; these are development-data observations only and do not describe production. No database values were changed by the report. Ruby syntax and focused RuboCop checks passed.

## Production read-only preflight (2026-10-04)

The report connected to the database configured as `DATABASE_URL_PROD_neon` and ran inside PostgreSQL `READ ONLY`. All five identity migration versions are pending. The inspected core tables report zero rows; `player_coaches` is absent. The report therefore emitted one blocker (`required_tables_missing`) and one warning (`required_migrations_pending`), with the missing table named in `missing_required_tables` and its preservation count set to `null`. The report exited nonzero as designed. This surfaced an earlier report bug: it previously raised on the absent table without producing diagnostics; missing required tables are now reported explicitly.

This is only evidence about the configured URL. It does not verify that the URL is the intended live customer database. A read-only listing of the configured R2 bucket found no objects under the active Neon backup prefix, so there is no backup object or checksum to validate. No decryption/restore proof or deployment approval was available in the workspace, and no migration was attempted. Confirm the target with the production operator, create and verify a restorable backup, reconcile the missing baseline table through the reviewed migration/release, then rerun the preflight before deployment.

The checked-in Kamal deployment configuration also still points to a private example host (`192.168.0.1`) and a local image registry (`localhost:5555`); it does not identify a reachable production release target. GitHub CLI is unavailable in this workspace, so the repository backup workflow cannot be dispatched here. A production rollout cannot be performed from the current deployment configuration.

## Remaining operational gate

Production rollout remains incomplete until the intended database and deployment targets are confirmed, a fresh restorable backup is retained, the missing baseline schema is reconciled, migrations are deployed, and a clean post-migration report is retained. The current read-only preflight found a blocker, and the checked-in deploy target is a placeholder, so deployment is not ready.

## Issue 225 readiness gate update (2026-10-05)

The original readiness task only required the first five identity migrations and did not inspect the unified invitation or profile-merge audit tables. That gate is insufficient for Issue 225. `IdentityProductionReadinessReport` now requires all seventeen identity/Issue 225 migrations, including `20261006100006`, requires the claim/invitation/consolidation/merge tables, reports their row counts, and checks polymorphic claim, invitation, and merge references plus invitation actor/timestamp state. The 2026-10-04 production report is historical evidence and did not evaluate this expanded migration set; rerun the updated report after the target and recovery gates are satisfied.

The last migration removes a global uniqueness rule on active invitation email addresses. The supported invariant is one active invitation per claimable subject. The same verified email may receive links for multiple distinct profiles or People, consistent with the multiple-profiles-per-person model.

## Issue 228 readiness gate update (2026-10-06)

[Issue 228 Phase 12](IDENTITY_228_PHASE_12_PRODUCTION_ROLLOUT_CLEANUP.md) extends the aggregate readiness gate through migrations `20261006100008`–`20261006100010`, checks that each Account has its required ContactDetail, verifies Account-backed profile/claim references, and includes ContactDetails in preservation counts. The earlier 17-migration result above is historical and does not represent the current Issue 228 gate.

The updated task was run read-only against the local development database: all 21 required identity migrations were applied, required tables were present, and the report emitted zero blockers/orphans with two duplicate-identity warning groups. This is not production evidence and does not clear the existing target/backup/deployment blockers.

## Local development reconciliation (2026-10-06)

After the Phase 11 suite passed, the read-only readiness report was run against the configured local development database before applying pending Issue 225 migrations. It found the final three migrations pending, no missing baseline tables, two used unified invitations without `used_by_id`, and no orphan references. Aggregate-only inspection confirmed both missing actors could be recovered from their retained legacy player invitation rows and claimant Accounts. The report also found two possible duplicate-email groups and one possible duplicate-name group; these remain warnings and were not merged.

Applied `20261006100004_reconcile_legacy_claim_invitations`, `20261006100005_allow_multiple_active_claim_invitees`, and `20261006100006_revoke_archived_profile_invitations` to the local development database. The reconciler's unresolved issuer, claimant, and token-subject mismatch guards all returned zero. Post-migration read-only readiness reports **17/17 migrations applied, zero blockers, and zero orphans**. The two missing actors are now populated from legacy records. The duplicate identity warnings remain for review. This local development result does not establish production readiness.
