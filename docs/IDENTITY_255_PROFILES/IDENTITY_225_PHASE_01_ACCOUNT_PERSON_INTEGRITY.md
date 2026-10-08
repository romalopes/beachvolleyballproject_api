# Issue 225 — Phase 1: Account–Person database integrity

**Status:** Implemented; migrations are applied to the local test and development databases. Existing development data reports 0 accounts without a Person. The historical null-link backfill path had no representative row in the rehearsal; production remains unverified. Depends on Phase 0.

## Objective

Make the database guarantee that every persisted Account belongs to exactly one Person, while preserving the existing one-Account-per-Person constraint. An Account is not created merely to make a user exist; changing signup provisioning is outside this phase unless Phase 0 demonstrates it is required.

## Scope

- Confirm the current Account callbacks and all Account creation paths.
- Measure Accounts with a null Person and duplicate Account-to-Person links.
- Backfill only null Account links. Create a Person from trustworthy User data, label it as system-created, and make the migration safe to rerun.
- Add the non-null database constraint after the backfill and preflight assertions pass.
- Ensure application creation paths assign or build the Person in the same transaction and translate uniqueness conflicts into a safe user-facing error.
- Remove Account transitional setters only if a call-site audit proves they are unused; do not combine unrelated signup redesign.

## Data safety

Do not merge records based on email or name. Preserve Account and Person IDs whenever possible. The migration must stop with actionable diagnostics if required user data cannot produce a valid Person. Document rollback limits once data has been written under the new constraint.

## Acceptance criteria

- `accounts.person_id` is non-null and has a unique index.
- Every Account has one Person; no Person has more than one Account.
- Account creation is atomic and does not create duplicate People.
- Existing accountless Users remain valid if the product permits them; the invariant applies to Accounts, not all Users.

## Verification

Migration tests for null backfill, rerun behavior, invalid rows, and uniqueness; model/controller tests for Account creation races; schema checks; rehearsal against a production-shaped database snapshot. Preserve before/after row counts and IDs.

## Implementation record

Added `20261006100001_enforce_person_on_accounts`. It backfills only null Account links from User name/email, aborts if any null link remains, and then applies `NOT NULL`. Rollback relaxes the constraint but retains generated People. The Account association is now required in the model. The migration applied successfully to `beachvolleyballproject_test`; no representative null-Account fixture was present in the rehearsal evidence.
