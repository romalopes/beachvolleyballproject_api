# Issue 228 — Phase 9: Retire People workflows

## Status

**The frontend Person management workflow was removed. The Account↔Person bridge is now removed in the application code and an additive/backfill/contract migration is prepared as `20261006100011`. Phase 9 remains partial:** Person still represents accountless roster members and legacy training/assessment history, so the People model, roster endpoints, and historical `person_id` columns are intentionally retained.

No `people` table or profile/history Person columns are dropped. The new migration removes only `accounts.person_id` after migrating active Account ownership and actor references. Applying it requires a deliberate database rollout.

## Changes in this phase

- Player and Coach creation now records profile display name and volleyball attributes only. The UI no longer searches for People, creates People, records contact details, links a profile to a Person, or suggests Person duplicates.
- Player and Coach edit pages update profile-owned fields only. Legacy Person/contact data and Account data are not edited through these forms.
- Player and Coach detail/catalogue surfaces no longer show legacy Person email, phone, date of birth, or creation-source fields. Account linking is described in account/profile language.
- Identity no longer displays a Person ID or redeems legacy Person-to-Account invitation tokens; the active redemption path is profile claim invitations.
- Coach profile creation and update now accept `display_name`, matching the existing nullable/personless CoachProfile schema.
- Profile names resolve from `display_name` first and fall back to the legacy Person name. Existing Person-backed records remain readable while migrated.
- `Account` no longer belongs to `Person`; `User` no longer exposes a Person-through-Account association. ContactDetail is the required Account-owned private identity record.
- The Account bridge migration copies Account ownership into profile and membership Account links, maps account actors for claims/invitations and organisation ownership, then removes `accounts.person_id`. Legacy Person rows remain available for roster/history compatibility.
- The Identity page no longer exposes Person consolidation.
- Profile invitation history no longer offers a People filter or displays legacy Person invitation rows. The supported flow is profile claims and profile invitations.
- There is no active `/people` page or navigation entry. Existing profile edit URLs remain `/players/:id/edit` and `/coaches/:id/edit`.

## Dependency audit

The frontend no longer offers Person creation, Person editing, Person duplicate lookup, or Person consolidation as a profile-management workflow. The `GET /api/v1/people` compatibility endpoint remains because organisation roster management still searches for Person-backed membership subjects.

The backend is **not** dependency-free. Confirmed active dependencies include:

- `OrganisationMembership` and `GroupMembership` still retain Person roster subjects for people without Accounts. Account-linked memberships now also carry `account_id`; authorization uses Account links for signed-in users.
- PlayerProfile and CoachProfile retain optional `person_id` for existing records, profile visibility within organisation peers, legacy serializers, and old claim/invitation compatibility.
- Training, assessments, roster search, Person invitation/consolidation, and deletion guards still contain Person-backed reads or foreign keys. They preserve people who have no Account and historical domain rows.
- Historical Person foreign keys and records remain in the database and are not orphaned by this phase because no rows were deleted or repointed.

Removing every remaining Person dependency would require a durable roster identity independent of both Account and Person, plus migration of all history and APIs. That broader removal is not part of `20261006100011`. Therefore the Phase 9 prompt's requirement “No active model or API depends on Person” is **not met** and Phase 9 remains incomplete. The narrower Account↔Person dependency is removed by the implementation in this checkout once the migration is applied.

## Verification checklist

- [x] Profile create/edit UI no longer creates or changes Person/contact data.
- [x] Person consolidation UI removed from Identity.
- [x] Person invitation subjects removed from the active management history UI.
- [x] No People route or navigation item is present.
- [x] Account and User models do not reference Person; profile ownership, membership authorization, claim actors and invitation actors use Account.
- [ ] No active model/API depends on Person — still blocked by accountless roster members and training/history compatibility described above.
- [ ] Dependency-free production verification report — pending completion of those migrations.
- [ ] Existing authentication, training, assessment, organisation, and group workflows verified after the full cutover — not claimed in this phase.
- [x] Person tables and non-Account foreign keys retained for roster/history compatibility.

Focused verification for the implemented slice:

- Frontend API, profile, Identity, management-dashboard, and detail-page suites: **115 tests passed**.
- Frontend production build (`npm run build`): passed. Vite reports the existing large-chunk warning.
- Rails player/coach controller and model suites: **105 tests, 355 assertions, 0 failures/errors**.
- `git diff --check`: passed in both repositories.

## Files changed

- Frontend profile create/edit forms, profile details, catalogues, Identity, and profile-management UI.
- `CoachesController` permits profile display names; `PlayerProfile#full_name` and `CoachProfile#full_name` prefer profile display names and retain Person fallback.
- Frontend API input types permit coach display names.

## Remaining implementation boundary

The remaining backend cutover is not a safe column rename. Existing OrganisationMembership and GroupMembership rows are durable roster identities, including participants who have no Account. Training and assessment history also resolves those roster subjects through Person-backed references. Replacing these references with `account_id` alone would either lose unclaimed participants or make them impossible to roster before registration. The completed Account decoupling slice adds Account actor/owner links while preserving those roster identities.

The next implementation slice must introduce a durable roster identity independent of `Person` and `Account` (or another explicitly approved equivalent), then migrate memberships and historical participant references while preserving their IDs/meaning. Account and profile links can be optional links from that roster identity. ContactDetails remains private Account data and must not become a substitute for unregistered roster identities. After that:

1. Backfill the new roster identity for every canonical Person and preserve merge aliases/history.
2. Repoint organisation/group memberships and training/assessment participant resolution transactionally, preserving existing membership and history rows.
3. Move claim/invitation actor audit references to Account/User and retain immutable historical attribution.
4. Switch all API serializers, authorization, roster endpoints, and compatibility clients to the new identity source.
5. Verify authentication, rosters, training, assessments, and historical reports against the migrated data before considering Person API/model retirement.

Until that migration is designed and implemented, keep the Person-backed endpoints and foreign keys readable. Do not drop `people`, `person_id`, or compatibility endpoints, and do not describe Phase 9 as complete.
