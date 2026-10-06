# Issue 228 — Phase 12: Production rollout and cleanup

## Objective and current decision

Prepare a safe runbook for the independently deployed Rails API and React frontend, extend the aggregate-only readiness gate through the current Issue 228 schema, and record the production release decision.

**Go/no-go: NO-GO.** No production migration, deployment, or destructive cleanup was performed. The production database/deployment target is not confirmed, the checked-in Kamal host and registry remain placeholders, and the previous production preflight reported missing baseline schema and no verified restorable backup. That preflight is historical; it must be repeated against a confirmed target after recovery gates are satisfied.

Phase 9 is still partial because active Account and organisation/group roster workflows depend on `Person`. Phase 11 is also partial because repository-wide lint and production-like verification gaps remain. Therefore cleanup that drops Person tables/columns is out of scope and must wait for the dependency cutover, a stable observation period, and a separately approved contract migration.

## Readiness gate changes

`IdentityProductionReadinessReport` now requires the identity migration set through `20261006100010`, rather than stopping at `20261006100007`. It also:

- Counts ContactDetails and Account-linked profile rows without exposing identity values.
- Treats any Account without its required ContactDetail as a blocker.
- Checks orphaned ContactDetail, profile Account/creator Account, and claim claimant/reviewer Account references.
- Includes ContactDetails in pre/post preservation counts.

The report remains aggregate-only and the task runs it inside a PostgreSQL read-only transaction. A local development read-only run on 2026-10-06 reported all 21 required migrations applied, no missing tables, zero blockers, and two duplicate-identity warning groups. This is development evidence only; it says nothing about production state.

## Production preconditions

Do not schedule deployment until every item below has an owner and retained evidence:

1. Confirm the intended production database provider, database URL secret name, API host, frontend project/domain, and release owner. Never copy credentials into this document or logs.
2. Replace the Kamal placeholder host `192.168.0.1` and local registry `localhost:5555` with reviewed deployment values. Confirm the Vercel project points at the matching frontend/API release.
3. Run the existing encrypted database backup workflow against the confirmed provider. Record backup key, checksum, creation time and provider.
4. Run the existing restore-test workflow into a disposable database and retain successful checksum, decryption, restore and validation evidence. PostgreSQL backups do not include Supabase Active Storage objects; verify media recovery separately.
5. Restore a recent production backup to a production-sized staging database. Rehearse the exact release, readiness report and migrations there; measure migration duration, lock waits, table sizes, and application startup time.
6. Resolve all readiness blockers. Review duplicate email/name warnings manually without automatic merges. Compare all pre/post preservation counts and investigate unexplained differences.
7. Confirm the prior API and new API can each run against the expanded schema during the planned deployment overlap. In particular, exercise claims/invitations and the `declined` state across the actual release boundary.
8. Finish/accept the remaining Phase 9 and Phase 11 work or record an explicit release-owner decision that those limitations do not block this deployment.
9. Schedule a low-traffic window, pause identity-changing staff work, identify the recovery owner, and confirm current backups and rollback contacts.

## Migration inventory and operational risk

All changes use ordinary Rails/PostgreSQL DDL and transactional migrations; no concurrent index build is configured. Exact duration and lock impact must be measured against the restored production-sized copy.

| Migration | Change | Rollout and rollback risk |
| --- | --- | --- |
| `20261003000001` | Makes player Person link nullable and replaces unique profile Person indexes | Index removal/rebuild and column change can lock profile tables. Once multiple profiles exist for one Person, restoring uniqueness can fail or force loss of valid profiles. |
| `20261006000002` and `20261006100004` | Backfill/reconcile unified invitations from legacy tables | Writes invitation rows in bulk. Reconciler deliberately aborts on unresolved or mismatched subjects/actors. Legacy sources remain; compare counts and subject/actor invariants. |
| `20261006100001`–`00003` | Enforce Account/Person compatibility, add creator Account links, merge audit schema | Reference/constraint/index changes can lock profiles and people; creator backfills update profile rows. Do not delete audit records on rollback. |
| `20261006100005`–`00006` | Remove global invitation-email uniqueness and revoke invitations for archived profiles | Index drop is fast but irreversible semantics begin when duplicate active invitee emails are created; invitation revocation is one-way. A rollback must not reactivate those bearer tokens. |
| `20261006100007` | Creates ContactDetails, adds profile Account FKs, backfills contact and ownership data | Inserts one ContactDetail per Account and updates both profile tables. Bulk updates acquire row locks; index/FK creation and DDL may block writers. `down` drops ContactDetails and its data, so do not roll it back after it contains edits. |
| `20261006100008` | Adds Account actor links to claims, backfills, replaces pending-claim uniqueness | Backfills claim rows and changes a unique partial index. `down` is intentionally irreversible because valid competing Account claims may no longer fit the old index. |
| `20261006100009` | Adds and constrains claim verification method | Constraint validation scans claims and may lock the table. |
| `20261006100010` | Adds declined invitation state and replaces status check | Constraint replacement can lock/scan invitations. A rollback can fail after rows use `declined`; never delete those records to force rollback. |

The account/contact migration is additive to the previous Person-backed model, but API compatibility for old clients is not yet demonstrated. Migration completion alone does not establish application compatibility.

## Release sequence

1. Capture the pre-release read-only readiness JSON and retain it with the release record.
2. Confirm the backup restore proof and staging rehearsal are current for this exact application revision.
3. Choose one migration runner. Current `bin/docker-entrypoint` runs `bin/rails db:prepare` on Rails server startup; do not also launch a separate migration process concurrently. Prefer a single, explicitly observed runner before new API processes start if deployment topology is changed from the current one-host template.
4. Apply migrations in order and watch the PostgreSQL migration session, logs, lock waits and application health. Stop on an unexpected lock duration, unresolved migration error, or failed check; do not manually edit `schema_migrations`.
5. Deploy the API and wait for healthy responses. Verify the API reports all required migrations applied.
6. Deploy the frontend only after API compatibility checks pass. The frontend and API deploy independently; retain the prior frontend release until smoke checks complete.
7. Capture post-release readiness JSON. Require zero blockers and zero orphan counts. Explain every changed preservation count and record reviewed warnings.
8. Run non-mutating smoke reads: health, authenticated `/api/v1/me`, own Account/ContactDetails, profile visibility, claim status, and invitation status. Do not create real claims or consume invitation tokens as production smoke tests.
9. Monitor exceptions, 401/403/404/409/422 rates, database health, cache/queue health, email delivery, and support reports throughout the agreed observation period.
10. Record API/frontend release IDs, migration versions, backup reference, pre/post report locations, duration, approved warnings, smoke results, and operator sign-off.

## Rollback and recovery

- **Frontend regression:** restore the previous Vercel frontend release. This does not roll back API or database changes.
- **API regression before schema writes:** redeploy the previous API only after confirming it tolerates all additive columns/status values. Do not infer compatibility from schema shape alone.
- **Migration failure:** stop API rollout; inspect transaction and `schema_migrations` state. Retry only after confirming the failed migration rolled back cleanly and the cause is understood.
- **Schema or data regression after writes:** prefer a forward fix. Several identity migrations have irreversible or data-loss-prone down paths; do not run `db:rollback` as a default response.
- **Backup restore:** the recovery owner must approve restoring to a new database and switching connections. Restore loses writes made after the backup and does not restore object storage/media.
- **Final destructive cleanup:** requires its own approved migration, fresh restorable backup, successful restore rehearsal, and a separately reviewed rollback/recovery plan. A database rollback cannot recreate deleted identity data.

Never delete profiles, merge identities, drop Person tables/columns, or manually modify migration history during incident recovery.

## Final cleanup gate

Person cleanup is **deferred**. Before a separately approved contract migration:

- Complete Phase 9 dependency cutover for Accounts, ContactDetails, organisation/group memberships, claims and all history references.
- Keep the app on the transitional schema through a recorded stable observation period.
- Demonstrate zero reads/writes to legacy Person paths with instrumentation or equivalent evidence.
- Prepare explicit data preservation, migration, restore, rollback and API compatibility procedures.
- Update API docs, frontend types, entity diagrams and operational reports.

## Release checklist and decision record

- [ ] Production DB and provider confirmed by release owner.
- [ ] Kamal API host/registry and frontend deployment target reviewed and confirmed.
- [ ] Fresh encrypted backup created and checksum recorded.
- [ ] Restore test into disposable DB passed; media recovery reviewed.
- [ ] Production-sized rehearsal passed with duration/lock measurements retained.
- [ ] Updated read-only readiness report has zero blockers and zero orphan counts.
- [ ] Pre/post row and preservation counts reconcile.
- [ ] Old/new API compatibility verified for the release overlap.
- [ ] Phase 9/11 limitations accepted or resolved by release owner.
- [ ] Maintenance window, recovery owner and monitoring plan confirmed.
- [ ] API then frontend smoke checks passed; observation owner assigned.
- [ ] No destructive cleanup included in this release.

**Current decision: NO-GO.** Production target/host and restore proof are not established in the workspace. Re-evaluate this checklist with the production operator; this document does not authorize deployment.
