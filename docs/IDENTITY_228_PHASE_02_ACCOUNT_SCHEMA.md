# Issue 228 — Phase 2: Account-centric schema and backfill

## Status

Implemented and verified against the configured local PostgreSQL database. Work stops at this issue checkpoint; no Phase 3 ownership or authorization changes are included.

## Decisions applied

- Every Account receives one private ContactDetail with first name, last name, contact email, phone and date of birth.
- ContactDetail email is distinct from User.email_address (authentication).
- AccountAddress continues to hold postal address fields.
- PlayerProfile and CoachProfile gain nullable `account_id` links. Person-linked profiles are linked only through the existing Account.person relationship; profiles with no Account remain unclaimed.
- Creator Account columns already existed. Legacy `created_by_id` User IDs are mapped to Accounts only where an exact Account exists.
- Roles stay on User. Person and existing Person references remain in place.
- Foreign keys use restrictive deletion behavior. No domain history is deleted.

## Changes

- Added migration `20261006100007_add_account_centric_identity_links` to create `contact_details`, add profile `account_id` FKs, backfill ContactDetails from Account-linked Person data, backfill profile Account links, and fill missing creator Account links from an exact User mapping.
- Added `ContactDetail` and Account association/creation validation. Account creation builds ContactDetail in the same Active Record transaction. Existing Person writes synchronize the ContactDetail during this transition.
- Exposed contact email in the existing account API and account settings form without changing the User login email.
- Added `AccountIdentityPhase2Backfill` and `bin/rails identity:phase2_backfill`. The default is a read-only dry run; set `APPLY=true` to repeat the idempotent account/profile creator mapping. It reports core counts, unknown creator mappings, profiles with accountless Person records, ambiguities, and preserved history counts.
- Added Account collections for zero or more player and coach profiles. Account and profile deletion is restricted while these ownership links exist.
- New profiles inherit an Account only when their linked Person already has that verified Account; accountless profiles stay unclaimed.
- Extended the production readiness report with the new table and migration version.

## Verification results

Run from `beachvolleyballproject_api`:

```sh
bin/rails db:migrate
bin/rails identity:phase2_backfill
APPLY=true bin/rails identity:phase2_backfill
bin/rails identity:phase2_backfill
bin/rails test test/models/account_test.rb test/controllers/api/v1/accounts_controller_test.rb
```

 - `bin/rails db:migrate`: passed; migration `20261006100007` is `up`.
 - `bin/rails identity:phase2_backfill`: passed in dry-run mode.
 - `APPLY=true bin/rails identity:phase2_backfill` followed by dry run: passed; repeated mapping did not change counts.
 - Final dry-run snapshot: 10 Users, 4 Accounts, 32 People, 11 Person-linked profiles, 10 profile Account links, 1 profile without an Account, and 0 Accounts without ContactDetails.
 - Ambiguous Person→Account mappings: 0. Ambiguous creator User→Account mappings: 0.
 - Profile Account/Person conflicts: 0.
 - Orphan foreign keys: 0 for Accounts and for both profile types across Person, Account, creator User and creator Account links.
 - Historical rows at final preflight: 19 group memberships; 0 each for assessments, training participants, assessment participants, player-coach periods and organisation memberships. Before/after backfill counts matched.
 - `bin/rails test test/models/account_test.rb test/controllers/api/v1/accounts_controller_test.rb test/services/account_identity_phase2_backfill_test.rb`: 24 tests, 81 assertions, 0 failures/errors.
 - Frontend `npx tsc --noEmit`: passed.

Production application is outside this phase. The Person model/table and Person-backed workflows remain active; continue only after reviewing this Phase 2 checkpoint.
